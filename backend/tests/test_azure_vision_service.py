import base64
import io
import json

import pytest
import requests
from fastapi import HTTPException
from fastapi.testclient import TestClient
from PIL import Image

import azure_vision_service as service


ANALYSIS_RESULT = {
    "environment": {"name": "kitchen", "confidence": 0.95},
    "objects": [],
    "hazards": [],
    "narration": "Kitchen ahead.",
    "immediate_warning": None,
}


class FakeResponse:
    def __init__(self, result=None, error=None):
        self.result = result
        self.error = error
        self.status_code = error.response.status_code if error else 200
        self.headers = error.response.headers if error else {}

    def raise_for_status(self):
        if self.error:
            raise self.error

    def json(self):
        return self.result


@pytest.fixture
def jpeg_bytes():
    output = io.BytesIO()
    Image.new("RGB", (2, 2), "white").save(output, format="JPEG")
    return output.getvalue()


@pytest.fixture
def client():
    return TestClient(service.app)


def encoded_image(content):
    return base64.b64encode(content).decode("ascii")


def mock_analysis(monkeypatch):
    monkeypatch.setattr(
        service,
        "call_azure_openai_vision",
        lambda *args, **kwargs: ANALYSIS_RESULT,
    )


def configure_provider(monkeypatch):
    monkeypatch.setattr(service, "AZURE_OPENAI_ENDPOINT", "https://example.test")
    monkeypatch.setattr(service, "AZURE_OPENAI_API_KEY", "test-key")
    monkeypatch.setattr(service, "AZURE_OPENAI_DEPLOYMENT", "gpt-4o")


def test_analyze_image_accepts_valid_jpeg(client, jpeg_bytes, monkeypatch):
    mock_analysis(monkeypatch)

    response = client.post(
        "/api/v1/analyze-image",
        json={
            "image_base64": encoded_image(jpeg_bytes),
            "image_mime_type": "image/jpeg",
            "request_type": "scene_narration",
            "language": "en-US",
        },
    )

    assert response.status_code == 200
    assert response.json()["environment"] == {
        "name": "kitchen",
        "confidence": 0.95,
    }


def test_upload_image_passes_form_options(client, jpeg_bytes, monkeypatch):
    received = {}

    def fake_analysis(image_base64, mime_type, request_type, language):
        received["request_type"] = request_type
        received["language"] = language
        return ANALYSIS_RESULT

    monkeypatch.setattr(service, "call_azure_openai_vision", fake_analysis)

    response = client.post(
        "/api/v1/upload-image",
        files={"file": ("room.jpg", jpeg_bytes, "image/jpeg")},
        data={"request_type": "hazard_assessment", "language": "es-MX"},
    )

    assert response.status_code == 200
    assert received == {
        "request_type": "hazard_assessment",
        "language": "es-MX",
    }


@pytest.mark.parametrize(
    ("payload", "mime_type", "expected_detail"),
    [
        (b"not an image", "image/jpeg", "Invalid or corrupt image"),
        (b"not-base64!", "image/jpeg", "Invalid base64 image data"),
    ],
)
def test_analyze_image_rejects_invalid_data(
    client, payload, mime_type, expected_detail
):
    image_base64 = (
        payload.decode("ascii")
        if payload == b"not-base64!"
        else encoded_image(payload)
    )

    response = client.post(
        "/api/v1/analyze-image",
        json={"image_base64": image_base64, "image_mime_type": mime_type},
    )

    assert response.status_code == 400
    assert response.json()["detail"] == expected_detail


def test_analyze_image_rejects_mime_mismatch(client, jpeg_bytes):
    response = client.post(
        "/api/v1/analyze-image",
        json={
            "image_base64": encoded_image(jpeg_bytes),
            "image_mime_type": "image/png",
        },
    )

    assert response.status_code == 400
    assert "does not match" in response.json()["detail"]


def test_analyze_image_rejects_oversized_file(
    client, jpeg_bytes, monkeypatch
):
    monkeypatch.setattr(service, "MAX_IMAGE_SIZE_MB", 0)

    response = client.post(
        "/api/v1/analyze-image",
        json={
            "image_base64": encoded_image(jpeg_bytes),
            "image_mime_type": "image/jpeg",
        },
    )

    assert response.status_code == 413


@pytest.mark.parametrize(
    ("request_type", "expected_instruction"),
    [
        ("scene_narration", "concise overview"),
        ("object_detection", "identifying objects"),
        ("hazard_assessment", "Prioritize hazards"),
    ],
)
def test_provider_payload_uses_request_type_and_language(
    monkeypatch, request_type, expected_instruction
):
    configure_provider(monkeypatch)
    captured = {}

    def fake_post(url, headers, json, timeout):
        captured.update(json)
        result = {
            "choices": [{"message": {"content": json_module.dumps(ANALYSIS_RESULT)}}]
        }
        return FakeResponse(result)

    json_module = json
    monkeypatch.setattr(service.requests, "post", fake_post)

    service.call_azure_openai_vision(
        "image-data", "image/jpeg", request_type, "es-MX"
    )

    instruction = captured["messages"][1]["content"][1]["text"]
    assert expected_instruction in instruction
    assert "Mexican Spanish" in instruction
    assert "Do not return those values in English" in instruction


def test_provider_timeout_returns_gateway_timeout(monkeypatch):
    configure_provider(monkeypatch)
    monkeypatch.setattr(
        service.requests,
        "post",
        lambda *args, **kwargs: (_ for _ in ()).throw(requests.Timeout()),
    )

    with pytest.raises(HTTPException) as error:
        service.call_azure_openai_vision("data", "image/jpeg")

    assert error.value.status_code == 504


def test_provider_throttling_preserves_retry_after(monkeypatch):
    configure_provider(monkeypatch)
    response = requests.Response()
    response.status_code = 429
    response.headers["Retry-After"] = "12"
    http_error = requests.HTTPError(response=response)
    monkeypatch.setattr(
        service.requests,
        "post",
        lambda *args, **kwargs: FakeResponse(error=http_error),
    )

    with pytest.raises(HTTPException) as error:
        service.call_azure_openai_vision("data", "image/jpeg")

    assert error.value.status_code == 429
    assert error.value.headers == {"Retry-After": "12"}


def test_provider_rejects_malformed_json(monkeypatch):
    configure_provider(monkeypatch)
    monkeypatch.setattr(
        service.requests,
        "post",
        lambda *args, **kwargs: FakeResponse(
            {"choices": [{"message": {"content": "not-json"}}]}
        ),
    )

    with pytest.raises(HTTPException) as error:
        service.call_azure_openai_vision("data", "image/jpeg")

    assert error.value.status_code == 500


def test_provider_requires_configuration(monkeypatch):
    monkeypatch.setattr(service, "AZURE_OPENAI_ENDPOINT", "")
    monkeypatch.setattr(service, "AZURE_OPENAI_API_KEY", None)

    with pytest.raises(HTTPException) as error:
        service.call_azure_openai_vision("data", "image/jpeg")

    assert error.value.status_code == 503