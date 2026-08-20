# 11 — Security, Privacy, and Platform Policy

## Security boundaries

- OAuth credentials/tokens are sensitive.
- Extracted stream URLs may be signed/ephemeral and should not be logged in full.
- API keys and client IDs belong in configuration; secrets/refresh material must never be committed.
- Real Google passwords, cookies, and 2FA material are forbidden in CI and agent prompts.
- Downloaded media remains local unless the user explicitly exports it.

## Logging redaction

Redact or avoid:

- `Authorization` headers;
- access/refresh tokens;
- signed media URL query parameters;
- Google account email if not required for debugging;
- filesystem paths that reveal unexpected sensitive data.

## YouTube policy reality

Google's YouTube API developer-policy guide states that API clients should not allow offline YouTube downloads outside the YouTube Premium experience and should not separate audio/video through the API service.

FocusTube's media extraction path uses an unofficial extractor rather than a documented YouTube Data API media-download feature. This repository does **not** represent that this behavior is endorsed or authorized by YouTube merely because the user has YouTube Premium or because the project is personal use.

Engineering implications:

- keep YouTube Data API usage separate from extraction/download implementation;
- do not claim policy compliance for custom extraction/download behavior;
- do not add DRM/access-control circumvention mechanisms;
- do not add features intended to redistribute downloaded content;
- if commercialization/public distribution ever becomes a goal, perform a new legal/platform-policy review before proceeding.

## Privacy defaults

- no analytics SDK;
- no crash telemetry by default;
- no backend profile database;
- local history and progress stay on device;
- request minimal Google scopes.
