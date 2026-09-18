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
FARO_VISION_TOKEN=long-random-token-issued-to-the-iPhone
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

## Manual iOS-contract smoke test

Use a JPEG, PNG, or HEIC still image and a token loaded from the local ignored
`.env` file:

```bash
curl --fail-with-body -X POST http://127.0.0.1:8000/v1/scene-descriptions \
  -H "Authorization: Bearer $FARO_VISION_TOKEN" \
  -H "X-Request-ID: 018f3f51-7f78-7b72-b941-f2c20aca1742" \
  -F 'image=@scene.jpg;type=image/jpeg' \
  -F 'options={"request_id":"018f3f51-7f78-7b72-b941-f2c20aca1742","locale":"en-US","detail":"brief","prompt":"Describe nearby objects and immediate obstacles."};type=application/json'
```

The endpoint replies with a compact speech description, requested language,
optional confidence, provider-model identifier, and processing duration.

## iOS contract endpoint

The iOS app uses the authenticated contract endpoint:

```text
POST /v1/scene-descriptions
Authorization: Bearer <FARO_VISION_TOKEN>
X-Request-ID: <UUID matching options.request_id>
```

It accepts the `image` and JSON `options` multipart fields defined in
[`docs/vision-api-contract.md`](../docs/vision-api-contract.md), validates a
10 MB original-image limit, and returns the compact speech response consumed by
`FAROVisionClient`.

- JPEG and PNG are forwarded to Azure after content validation.
- HEIC is decoded locally and normalized to JPEG before Azure inference.
- Requests use a process-local limit of 10 per minute by default. Override only
  with `FARO_VISION_RATE_LIMIT_PER_MINUTE` for controlled testing.
- `FARO_VISION_TOKEN` is the only credential that belongs in the iPhone's
  ignored `Local.xcconfig`; Azure credentials remain server-side.

The default process bind is `127.0.0.1:8000`. Do not set `API_HOST=0.0.0.0`
unless the service is placed behind a private authenticated reverse proxy.

## Historical prototype implementation

The former `/api/v1/upload-image` and `/api/v1/analyze-image` implementations
are retained as unregistered code during the transition, but they have no HTTP
route and return `404`. The iOS contract endpoint above is the only inference
surface exposed by the service.
