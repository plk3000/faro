"""
Azure OpenAI Vision Service for FARO
Image analysis and environment/object categorization
"""

import os
import json
import base64
import binascii
import io
import logging
import uuid
from datetime import datetime, timezone
from typing import Optional, Dict, Any, List, Literal

import requests
from fastapi import FastAPI, HTTPException, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from PIL import Image, UnidentifiedImageError
from pydantic import BaseModel, Field
import dotenv

# Load environment variables
dotenv.load_dotenv()

# Configure logging (NO image payloads)
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration
AZURE_OPENAI_ENDPOINT = os.getenv("AZURE_OPENAI_ENDPOINT", "").rstrip("/")
AZURE_OPENAI_API_KEY = os.getenv("AZURE_OPENAI_API_KEY") or os.getenv("API_KEY")
AZURE_OPENAI_DEPLOYMENT = (
    os.getenv("AZURE_OPENAI_DEPLOYMENT_NAME")
    or os.getenv("AZURE_OPENAI_MODEL")
)
AZURE_OPENAI_API_VERSION = os.getenv("AZURE_OPENAI_API_VERSION", "2024-08-01-preview")

MAX_IMAGE_SIZE_MB = int(os.getenv("MAX_IMAGE_SIZE_MB", "5"))
REQUEST_TIMEOUT_SEC = int(os.getenv("REQUEST_TIMEOUT_SECONDS", "30"))
IMAGE_DETAIL = os.getenv("AZURE_OPENAI_IMAGE_DETAIL", "low")

# System prompt for environment and object categorization
SYSTEM_PROMPT = """You are an accessibility assistant analyzing camera images for a blind user's navigation system called FARO.

Your task is to:
1. Identify the ENVIRONMENT (Kitchen, Living Room, Bedroom, Bathroom, Hallway, Office, Front Door, Garage, Stairs, etc.)
2. Detect OBJECTS and their positions relative to the user
3. Identify HAZARDS (obstacles, stairs, open doors, etc.)
4. Generate a SHORT accessibility-focused NARRATION (under 20 words)

Return ONLY valid JSON in this format:
{
  "environment": {
    "name": "string (e.g., 'kitchen')",
    "confidence": 0.0-1.0
  },
  "objects": [
    {
      "name": "string (e.g., 'chair')",
      "position": "center|left|right|ahead|behind|above|below",
      "is_hazard": boolean,
      "hazard_type": "obstacle|stairs|door|open_space|drop-off|other|none"
    }
  ],
  "hazards": [
    {
      "type": "string",
      "description": "string",
      "severity": "low|medium|high",
      "position": "string"
    }
  ],
  "narration": "string (short, clear, under 20 words)",
  "immediate_warning": "null|string"
}

IMPORTANT:
- Use relative positioning ONLY (left, right, ahead, behind, center)
- Focus on spatial relationships and hazards
- NO visual color/texture descriptors
- Keep narration very short and actionable
- Prioritize safety-critical information"""


# Request/Response Models
class ImageAnalysisRequest(BaseModel):
    image_base64: str
    image_mime_type: str = "image/jpeg"
    request_type: Literal[
        "scene_narration", "object_detection", "hazard_assessment"
    ] = "scene_narration"
    language: Literal["en-US", "es-MX"] = "en-US"


class ObjectInfo(BaseModel):
    name: str
    position: str
    is_hazard: bool
    hazard_type: str


class HazardInfo(BaseModel):
    type: str
    description: str
    severity: str
    position: Optional[str] = None


class EnvironmentInfo(BaseModel):
    name: str
    confidence: float


class ImageAnalysisResponse(BaseModel):
    success: bool
    request_id: str
    environment: Optional[EnvironmentInfo] = None
    objects: List[ObjectInfo] = Field(default_factory=list)
    hazards: List[HazardInfo] = Field(default_factory=list)
    narration: Optional[str] = None
    immediate_warning: Optional[str] = None
    timestamp: str
    processing_time_ms: float


class ErrorResponse(BaseModel):
    success: bool = False
    error: Dict[str, str]
    request_id: str


# Initialize FastAPI app
app = FastAPI(
    title="FARO Azure Vision Service",
    description="Image analysis for blind user navigation",
    version="1.0.0"
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure for specific domains in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


IMAGE_FORMATS_BY_MIME_TYPE = {
    "image/jpeg": "JPEG",
    "image/png": "PNG",
    "image/webp": "WEBP",
    "image/gif": "GIF",
}

REQUEST_INSTRUCTIONS = {
    "scene_narration": "Prioritize a concise overview and actionable narration.",
    "object_detection": "Prioritize identifying objects and their relative positions.",
    "hazard_assessment": "Prioritize hazards, severity, position, and immediate warnings.",
}

LANGUAGE_INSTRUCTIONS = {
    "en-US": "Write every human-readable JSON value in English (United States).",
    "es-MX": (
        "Write every human-readable JSON value in Mexican Spanish. "
        "Translate environment names, object names, hazard descriptions, narration, "
        "and immediate warnings. Do not return those values in English."
    ),
}


def validate_image_bytes(content: bytes, mime_type: str, max_size_mb: int = 5) -> None:
    """Validate image size, decodability, and declared MIME type."""
    if mime_type not in IMAGE_FORMATS_BY_MIME_TYPE:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid MIME type. Allowed: {list(IMAGE_FORMATS_BY_MIME_TYPE)}"
        )

    if len(content) > max_size_mb * 1024 * 1024:
        raise HTTPException(
            status_code=413,
            detail=f"Image exceeds {max_size_mb} MB limit"
        )

    try:
        with Image.open(io.BytesIO(content)) as image:
            actual_format = image.format
            image.verify()
    except (UnidentifiedImageError, OSError, ValueError):
        raise HTTPException(status_code=400, detail="Invalid or corrupt image")

    if actual_format != IMAGE_FORMATS_BY_MIME_TYPE[mime_type]:
        raise HTTPException(
            status_code=400,
            detail="Image content does not match the declared MIME type"
        )


def decode_and_validate_image(
    image_base64: str,
    mime_type: str,
    max_size_mb: int = 5
) -> bytes:
    """Decode a base64 image and validate its content."""
    try:
        content = base64.b64decode(image_base64, validate=True)
    except (binascii.Error, ValueError):
        raise HTTPException(status_code=400, detail="Invalid base64 image data")

    validate_image_bytes(content, mime_type, max_size_mb)
    return content


def call_azure_openai_vision(
    image_base64: str,
    mime_type: str,
    request_type: str = "scene_narration",
    language: str = "en-US"
) -> Dict[str, Any]:
    """
    Call Azure OpenAI GPT-4 Vision to analyze image.
    Returns categorized environment and objects.
    """
    if not AZURE_OPENAI_ENDPOINT or not AZURE_OPENAI_API_KEY:
        raise HTTPException(
            status_code=503,
            detail="Azure OpenAI endpoint or API key is not configured"
        )

    if not AZURE_OPENAI_DEPLOYMENT:
        raise HTTPException(
            status_code=503,
            detail=(
                "Azure OpenAI deployment is not configured. Set "
                "AZURE_OPENAI_DEPLOYMENT_NAME or AZURE_OPENAI_MODEL."
            )
        )

    logger.info(
        "Preparing vision request: request_type=%s language=%s mime_type=%s",
        request_type,
        language,
        mime_type,
    )
    
    headers = {
        "api-key": AZURE_OPENAI_API_KEY,
        "Content-Type": "application/json"
    }
    
    # Build the request
    payload = {
        "messages": [
            {
                "role": "system",
                "content": SYSTEM_PROMPT
            },
            {
                "role": "user",
                "content": [
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": f"data:{mime_type};base64,{image_base64}",
                            "detail": IMAGE_DETAIL
                        }
                    },
                    {
                        "type": "text",
                        "text": (
                            "Analyze this image for a blind user navigation system. "
                            f"{REQUEST_INSTRUCTIONS[request_type]} "
                            f"{LANGUAGE_INSTRUCTIONS[language]} "
                            "Return ONLY the JSON response."
                        )
                    }
                ]
            }
        ],
        "response_format": {"type": "json_object"}
    }

    if AZURE_OPENAI_DEPLOYMENT.startswith("gpt-5") or "gpt-5" in AZURE_OPENAI_DEPLOYMENT:
        payload["max_completion_tokens"] = 1024
        payload["reasoning_effort"] = "minimal"
    else:
        payload["max_tokens"] = 256
        payload["temperature"] = 0.5
        payload["top_p"] = 0.95

    if AZURE_OPENAI_ENDPOINT.endswith("/openai/v1"):
        url = f"{AZURE_OPENAI_ENDPOINT}/chat/completions"
        payload["model"] = AZURE_OPENAI_DEPLOYMENT
    else:
        url = (
            f"{AZURE_OPENAI_ENDPOINT}/openai/deployments/"
            f"{AZURE_OPENAI_DEPLOYMENT}/chat/completions"
            f"?api-version={AZURE_OPENAI_API_VERSION}"
        )
    
    logger.info(f"Calling Azure OpenAI Vision API (deployment: {AZURE_OPENAI_DEPLOYMENT})")
    
    try:
        response = requests.post(
            url,
            headers=headers,
            json=payload,
            timeout=REQUEST_TIMEOUT_SEC
        )
        response.raise_for_status()
        
        result = response.json()
        
        # Extract the content from the response
        if "choices" in result and len(result["choices"]) > 0:
            content = result["choices"][0]["message"]["content"]
            
            # Parse JSON from response
            try:
                analysis = json.loads(content)
                return analysis
            except json.JSONDecodeError:
                logger.error("Failed to parse vision API response as JSON")
                raise HTTPException(
                    status_code=500,
                    detail="Invalid response format from vision API"
                )
        else:
            raise HTTPException(
                status_code=500,
                detail="Unexpected response structure from vision API"
            )
    
    except requests.Timeout:
        logger.error("Vision API request timeout")
        raise HTTPException(
            status_code=504,
            detail="Vision analysis timeout - request took too long"
        )
    except requests.HTTPError as e:
        status_code = e.response.status_code if e.response is not None else 503
        logger.error(f"Vision API request failed with status {status_code}")
        if status_code == 429:
            retry_after = e.response.headers.get("Retry-After", "30")
            raise HTTPException(
                status_code=429,
                detail="Vision API rate limit exceeded; retry shortly",
                headers={"Retry-After": retry_after}
            )
        raise HTTPException(
            status_code=503,
            detail="Vision API unavailable"
        )
    except requests.RequestException as e:
        logger.error(f"Vision API request failed: {str(e)}")
        raise HTTPException(
            status_code=503,
            detail="Vision API unavailable"
        )


@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {
        "status": "healthy",
        "service": "FARO Azure Vision Service",
        "timestamp": datetime.now(timezone.utc).isoformat()
    }


@app.post("/api/v1/analyze-image", response_model=ImageAnalysisResponse)
async def analyze_image(request: ImageAnalysisRequest) -> ImageAnalysisResponse:
    """
    Analyze an image and categorize environment, objects, and hazards.
    
    Args:
        request: ImageAnalysisRequest with base64-encoded image
    
    Returns:
        ImageAnalysisResponse with categorization and narration
    """
    
    request_id = str(uuid.uuid4())
    start_time = datetime.now(timezone.utc)
    
    try:
        logger.info(
            "[%s] Image analysis request received: request_type=%s "
            "language=%s mime_type=%s",
            request_id,
            request.request_type,
            request.language,
            request.image_mime_type,
        )
        
        # Validate image
        decode_and_validate_image(
            request.image_base64,
            request.image_mime_type,
            MAX_IMAGE_SIZE_MB
        )
        
        logger.info(f"[{request_id}] Image validation passed")
        
        # Call Azure OpenAI Vision API
        analysis_result = call_azure_openai_vision(
            request.image_base64,
            request.image_mime_type,
            request.request_type,
            request.language
        )
        
        logger.info(f"[{request_id}] Vision analysis completed")
        
        # Build response
        environment = EnvironmentInfo(**analysis_result.get("environment", {}))
        
        objects = [
            ObjectInfo(**obj) for obj in analysis_result.get("objects", [])
        ]
        
        hazards = [
            HazardInfo(**h) for h in analysis_result.get("hazards", [])
        ]
        
        narration = analysis_result.get("narration", "")
        
        processing_time_ms = (datetime.now(timezone.utc) - start_time).total_seconds() * 1000
        
        logger.info(
            f"[{request_id}] Analysis complete - "
            f"Environment: {environment.name} ({environment.confidence:.2f}), "
            f"Objects: {len(objects)}, Hazards: {len(hazards)}, "
            f"Time: {processing_time_ms:.0f}ms"
        )
        
        return ImageAnalysisResponse(
            success=True,
            request_id=request_id,
            environment=environment,
            objects=objects,
            hazards=hazards,
            narration=narration,
            immediate_warning=analysis_result.get("immediate_warning"),
            timestamp=datetime.now(timezone.utc).isoformat(),
            processing_time_ms=processing_time_ms
        )
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"[{request_id}] Unexpected error: {str(e)}")
        raise HTTPException(
            status_code=500,
            detail="Internal server error"
        )


@app.post("/api/v1/upload-image")
async def upload_image_file(
    file: UploadFile = File(...),
    request_type: Literal[
        "scene_narration", "object_detection", "hazard_assessment"
    ] = Form("scene_narration"),
    language: Literal["en-US", "es-MX"] = Form("en-US")
) -> ImageAnalysisResponse:
    """
    Upload an image file directly (alternative to base64).
    """
    
    request_id = str(uuid.uuid4())
    
    # Validate file type
    if file.content_type not in ["image/jpeg", "image/png", "image/webp", "image/gif"]:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid file type: {file.content_type}"
        )
    
    # Read file and convert to base64
    content = await file.read()

    logger.info(
        "[%s] Multipart upload received: request_type=%s language=%s "
        "mime_type=%s size_bytes=%d",
        request_id,
        request_type,
        language,
        file.content_type,
        len(content),
    )
    
    validate_image_bytes(content, file.content_type, MAX_IMAGE_SIZE_MB)
    
    image_base64 = base64.b64encode(content).decode('utf-8')
    
    # Create request and analyze
    analysis_request = ImageAnalysisRequest(
        image_base64=image_base64,
        image_mime_type=file.content_type,
        request_type=request_type,
        language=language
    )
    
    return await analyze_image(analysis_request)


if __name__ == "__main__":
    import uvicorn
    
    port = int(os.getenv("API_PORT", "8000"))
    
    logger.info("=" * 50)
    logger.info("Starting FARO Azure Vision Service")
    logger.info(f"Endpoint: {AZURE_OPENAI_ENDPOINT}")
    logger.info(f"Deployment: {AZURE_OPENAI_DEPLOYMENT}")
    logger.info("=" * 50)
    
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=port,
        log_level="info"
    )
