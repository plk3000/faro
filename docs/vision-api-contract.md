# FARO Vision API Contract

This contract defines the boundary between the FARO iOS app and the separately
implemented FARO vision service. The service describes a user-selected still
image. The app does not continuously stream camera frames.

## Transport and versioning

- HTTPS is required outside local development.
- The initial endpoint is `POST /v1/scene-descriptions`.
- Breaking changes require a new URL version. Additive response fields are
  permitted, and clients must ignore unknown fields.
- Requests and responses use UTF-8.

## Authentication

Send an opaque service token:

```http
Authorization: Bearer <token>
```

The token is supplied through a local, gitignored iOS configuration file. It
must never be embedded in source control or written to application logs.

The client also sends the request identifier as `X-Request-ID`. It must match
the `request_id` in the multipart options object and is provided so gateways
can correlate a request without parsing the body.

## Request

Use `multipart/form-data` with these parts:

| Part | Content type | Required | Constraints |
|---|---|---:|---|
| `image` | `image/jpeg` or `image/heic` | yes | One still image, maximum 10 MB |
| `options` | `application/json` | no | Description options shown below |

`options`:

```json
{
  "request_id": "018f3f51-7f78-7b72-b941-f2c20aca1742",
  "locale": "en-US",
  "detail": "brief",
  "prompt": "Describe nearby objects, their relative position, and immediate obstacles in English."
}
```

- `request_id` is a client-generated UUID used for correlation and
  idempotency.
- `locale` is a BCP 47 language tag. The iOS prototype sends `en-US` or
  `es-MX` according to its current language setting.
- `detail` is `brief` or `detailed`; unknown values return `invalid_request`.
- `prompt` is optional application context, not an instruction to identify
  people or infer sensitive traits.

The server should honor repeated `request_id` values without performing
duplicate billable inference where practical.

## Success response

Status: `200 OK`

```json
{
  "request_id": "018f3f51-7f78-7b72-b941-f2c20aca1742",
  "description": "A wooden chair is about one metre ahead and slightly to the left.",
  "language": "en-US",
  "confidence": 0.86,
  "model": "provider/model-version",
  "processing_ms": 742
}
```

| Field | Type | Required | Meaning |
|---|---|---:|---|
| `request_id` | UUID string | yes | Echoes the request identifier |
| `description` | string | yes | Plain text suitable for immediate speech |
| `language` | BCP 47 string | yes | Must exactly echo the requested `locale` |
| `confidence` | number or null | yes | Calibrated `0...1`, or null when unavailable |
| `model` | string | yes | Stable provider/model revision identifier |
| `processing_ms` | integer | yes | Server-side processing duration |

`description` must not contain Markdown. It should lead with nearby hazards and
spatial relationships, avoid unsupported certainty, and remain under 500
characters for `brief` requests. The service must generate the description in
the requested language. The iOS client rejects a response whose `language`
does not match the request rather than speaking it with the wrong voice.

## Error response

All non-2xx responses use:

```json
{
  "request_id": "018f3f51-7f78-7b72-b941-f2c20aca1742",
  "error": {
    "code": "model_unavailable",
    "message": "Scene description is temporarily unavailable.",
    "retryable": true
  }
}
```

Supported status/code combinations:

| Status | Code | Retryable |
|---:|---|---:|
| 400 | `invalid_request` | no |
| 401 | `unauthorized` | no |
| 413 | `image_too_large` | no |
| 415 | `unsupported_image` | no |
| 429 | `rate_limited` | yes |
| 500 | `internal_error` | yes |
| 503 | `model_unavailable` | yes |
| 504 | `model_timeout` | yes |

For `429` and `503`, include `Retry-After` when known. The iOS client cancels
requests when the user begins a newer action and applies a finite timeout; the
service must tolerate disconnected clients.

## Privacy and retention

- Treat every image as sensitive home imagery.
- Do not retain request images or derived image data after inference by
  default.
- Do not use images for model training or human review without a separate,
  explicit opt-in.
- Logs may contain request IDs, timings, model revisions, status codes, and
  image byte counts, but never image bytes, prompts containing user data, auth
  tokens, GPS coordinates, or generated descriptions.
- If deployment infrastructure makes transient retention unavoidable, document
  the duration and storage boundary before enabling the live iOS client.

## Health check

`GET /health` returns `200 OK` with:

```json
{
  "status": "ok",
  "api_version": "v1"
}
```

Health status does not guarantee that a model is currently available.
