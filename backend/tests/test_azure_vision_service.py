import base64
import io
import json

import pytest
import requests
import pillow_heif
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


CONTRACT_REQUEST_ID = "018f3f51-7f78-7b72-b941-f2c20aca1742"


def contract_headers(token="test-contract-token", request_id=CONTRACT_REQUEST_ID):
    return {
        "Authorization": f"Bearer {token}",
        "X-Request-ID": request_id,
    }


def contract_options(request_id=CONTRACT_REQUEST_ID, locale="en-US"):
    return json.dumps(
        {
            "request_id": request_id,
            "locale": locale,
            "detail": "brief",
            "prompt": "Describe nearby obstacles.",
        }
    )


def configure_contract_token(monkeypatch):
    monkeypatch.setattr(service, "FARO_VISION_TOKEN", "test-contract-token")
    monkeypatch.setattr(service, "AZURE_OPENAI_DEPLOYMENT", "faro-vision-test")


def test_ios_contract_requires_bearer_token(client, jpeg_bytes, monkeypatch):
    configure_contract_token(monkeypatch)

    response = client.post(
        "/v1/scene-descriptions",
        files={"image": ("room.jpg", jpeg_bytes, "image/jpeg")},
        data={"options": contract_options()},
        headers={"X-Request-ID": CONTRACT_REQUEST_ID},
    )

    assert response.status_code == 401
    assert response.json() == {
        "request_id": CONTRACT_REQUEST_ID,
        "error": {
            "code": "unauthorized",
            "message": "Authorization is required.",
            "retryable": False,
        },
    }


def test_ios_contract_rejects_mismatched_request_ids(client, jpeg_bytes, monkeypatch):
    configure_contract_token(monkeypatch)

    response = client.post(
        "/v1/scene-descriptions",
        files={"image": ("room.jpg", jpeg_bytes, "image/jpeg")},
        data={"options": contract_options()},
        headers=contract_headers(request_id="not-the-options-request-id"),
    )

    assert response.status_code == 400
    assert response.json()["request_id"] == "not-the-options-request-id"
    assert response.json()["error"]["code"] == "invalid_request"


def test_ios_contract_accepts_uppercase_uuid_header(client, jpeg_bytes, monkeypatch):
    configure_contract_token(monkeypatch)
    mock_analysis(monkeypatch)
    uppercase_request_id = CONTRACT_REQUEST_ID.upper()

    response = client.post(
        "/v1/scene-descriptions",
        files={"image": ("room.jpg", jpeg_bytes, "image/jpeg")},
        data={"options": contract_options(request_id=uppercase_request_id)},
        headers=contract_headers(request_id=uppercase_request_id),
    )

    assert response.status_code == 200
    assert response.json()["request_id"] == CONTRACT_REQUEST_ID


def test_ios_contract_translates_azure_analysis(client, jpeg_bytes, monkeypatch):
    configure_contract_token(monkeypatch)
    mock_analysis(monkeypatch)

    response = client.post(
        "/v1/scene-descriptions",
        files={"image": ("room.jpg", jpeg_bytes, "image/jpeg")},
        data={"options": contract_options()},
        headers=contract_headers(),
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["request_id"] == CONTRACT_REQUEST_ID
    assert payload["description"] == "Kitchen ahead."
    assert payload["language"] == "en-US"
    assert payload["confidence"] == 0.95
    assert payload["model"] == service.AZURE_OPENAI_DEPLOYMENT
    assert isinstance(payload["processing_ms"], int)


def test_ios_contract_normalizes_heic_for_azure(client, monkeypatch):
    configure_contract_token(monkeypatch)
    mock_analysis(monkeypatch)
    pillow_heif.register_heif_opener()
    output = io.BytesIO()
    Image.new("RGB", (2, 2), "white").save(output, format="HEIF")

    response = client.post(
        "/v1/scene-descriptions",
        files={"image": ("room.heic", output.getvalue(), "image/heic")},
        data={"options": contract_options()},
        headers=contract_headers(),
    )

    assert response.status_code == 200


def test_contract_health_response(client):
    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok", "api_version": "v1"}


def test_ios_contract_wraps_missing_multipart_parts(client, monkeypatch):
    configure_contract_token(monkeypatch)

    response = client.post(
        "/v1/scene-descriptions",
        headers=contract_headers(),
    )

    assert response.status_code == 400
    assert response.json()["request_id"] == CONTRACT_REQUEST_ID
    assert response.json()["error"]["code"] == "invalid_request"


def test_legacy_inference_routes_are_not_registered(client):
    assert client.post("/api/v1/analyze-image", json={}).status_code == 404
    assert client.post("/api/v1/upload-image").status_code == 404
