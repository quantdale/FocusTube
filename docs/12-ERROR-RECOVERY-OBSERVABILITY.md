# 12 — Error Recovery and Observability

## Error taxonomy

Do not collapse all failures into `unknown`.

### MediaExtractionError

- networkUnavailable
- videoUnavailable
- regionRestricted
- ageRestricted
- extractorChanged
- noAllowedQuality
- malformedMetadata
- unknown(cause)

### DownloadError

- extractionFailed
- signedURLExpired
- networkInterrupted
- insufficientStorage
- componentValidationFailed
- muxFailed
- finalValidationFailed
- filesystemFailure
- cancelled

### YouTubeAPIError

- unauthenticated
- permissionDenied
- quotaExceeded(bucket)
- commentsDisabled
- resourceNotFound
- rateLimited
- transport
- decoding

## User-facing behavior

When the cause is known, say what failed and whether retry can help. Do not use generic "Something went wrong" for known operational states.

## Local observability

Use Apple's unified logging (`Logger`) with subsystems/categories such as:

- app;
- playback;
- extraction;
- download;
- mux;
- youtube-api;
- auth;
- persistence.

Log state transitions and identifiers, but redact signed URLs/tokens.

## Debug diagnostics bundle

Later milestone may export a user-triggered local diagnostics package containing sanitized app logs, version/toolchain info, state summaries, and failing video IDs—not media files or credentials.
