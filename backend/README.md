# FARO backend quick start

This FastAPI service sends a still image to an Azure OpenAI vision-capable
deployment and returns environment, object, hazard, and narration fields.

## Setup

From `backend/`, create and activate a virtual environment, then install the
dependencies.

PowerShell:

```powershell
py -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements-dev.txt
```

macOS or Linux:

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements-dev.txt
```

Create a local `.env` file in `backend/`:

```dotenv
AZURE_OPENAI_ENDPOINT=https://your-resource.openai.azure.com
AZURE_OPENAI_API_KEY=your-development-key
AZURE_OPENAI_DEPLOYMENT_NAME=your-vision-deployment (e.g. faro-gpt-5-mini)
```

`AZURE_OPENAI_ENDPOINT` may instead be an Azure OpenAI v1 endpoint ending in
`/openai/v1`. Do not commit `.env` or credentials.

## Run

```powershell
python azure_vision_service.py
```

The API starts at `http://localhost:8000`. Interactive OpenAPI documentation is
available at `http://localhost:8000/docs`.

Check that the process is responding:

```powershell
curl.exe http://localhost:8000/health
```

Run the tests with:

```powershell
python -m pytest
```

## Request examples

The shortest request uploads the included example image from `backend/`:

```powershell
curl.exe -X POST http://localhost:8000/api/v1/upload-image `
  -F "file=@img/example.webp;type=image/webp" `
  -F "request_type=scene_narration" `
  -F "language=en-US"
```

Request a hazard-focused response in Mexican Spanish:

```powershell
curl.exe -X POST http://localhost:8000/api/v1/upload-image `
  -F "file=@img/example.webp;type=image/webp" `
  -F "request_type=hazard_assessment" `
  -F "language=es-MX"
```

The JSON endpoint accepts the same image as base64:

```powershell
$image = [Convert]::ToBase64String(
  [IO.File]::ReadAllBytes((Resolve-Path "img/example.webp"))
)
$body = @{
  image_base64 = $image
  image_mime_type = "image/webp"
  request_type = "object_detection"
  language = "en-US"
} | ConvertTo-Json

Invoke-RestMethod `
  -Method Post `
  -Uri http://localhost:8000/api/v1/analyze-image `
  -ContentType "application/json" `
  -Body $body
```

Supported request types are `scene_narration`, `object_detection`, and
`hazard_assessment`. Supported languages are `en-US` and `es-MX`. Images may be
JPEG, PNG, WebP, or GIF and default to a 5 MB size limit.

These are the backend prototype routes. They do not yet implement the separate
iOS-facing `POST /v1/scene-descriptions` contract documented in
[`docs/vision-api-contract.md`](../docs/vision-api-contract.md).