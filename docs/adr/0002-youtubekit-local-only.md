# ADR-0002 — YouTubeKit Local Extraction Only

**Status:** Accepted

## Decision

Use YouTubeKit as the sole extractor and invoke local extraction only. Do not add yt-dlp fallback or YouTubeKit remote fallback.

## Consequence

Extraction may temporarily break when YouTube changes upstream behavior. FocusTube must surface this cleanly and update the pinned dependency after regression testing rather than silently routing through another extractor.
