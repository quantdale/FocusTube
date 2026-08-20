# 02 — Media Extraction and Playback

## Goal

Resolve a YouTube video ID into playable native streams using YouTubeKit local extraction and play the selected stream with AVPlayer/AVPlayerViewController.

## YouTubeKit policy

- Pin the verified stable release in `project.yml`.
- As of the repository research date (2026-08-20), the GitHub releases page reports **0.4.8** as latest.
- Use local extraction only. Do not enable `.remote`.
- Do not add yt-dlp as an alternate extractor.
- Wrap YouTubeKit behind `MediaExtracting` so upstream breakage is localized.

Conceptual protocol:

```swift
protocol MediaExtracting: Sendable {
    func resolve(videoID: String) async throws -> ResolvedMedia
}
```

`ResolvedMedia` should be a FocusTube-owned model, not a YouTubeKit `Stream` leaking through the app.

## Resolved media model

At minimum capture:

- video ID;
- extraction timestamp;
- combined streams;
- video-only streams;
- audio-only streams;
- resolution;
- codec/container indicators;
- native-playability flag;
- approximate/content length when supplied;
- source URL;
- expiration/re-resolution semantics if inferable.

## Allowed resolution filter

Before a stream is presented to product logic, apply the hard set:

```text
{1080, 720, 480, 360}
```

All other resolutions are ignored. The UI must never receive 1440/2160 options.

## Online playback selection

Initial policy:

1. prefer a natively playable combined video+audio stream;
2. resolution must be in the allowed set;
3. choose the highest allowed available resolution;
4. if no suitable combined stream exists, evaluate adaptive playback only after the basic viability gate is proven;
5. never silently select >1080p.

AVPlayer is the playback engine. AVPlayerViewController is the primary player UI because it provides the system playback experience and PiP support without building a fragile custom transport layer.

## PlaybackCoordinator responsibilities

- own the current AVPlayer lifecycle;
- ensure SwiftUI view recreation does not reset playback unexpectedly;
- expose current video/playback state to UI;
- record progress periodically and on significant lifecycle events;
- restore local resume position;
- coordinate audio session and Now Playing integration in later milestones;
- surface typed failures.

## Extraction failure behavior

Extraction failures are expected operational failures, not programmer crashes.

Classify at least:

- unavailable/private/deleted;
- age/region/restriction failure;
- extractor incompatibility/upstream change;
- no allowed stream quality;
- transient network failure;
- malformed response.

The UI may offer retry for retryable classes. No automatic switch to remote extraction is allowed.

## Live extractor smoke tests

Maintain a small set of stable public video IDs covering:

- ordinary combined-stream video;
- adaptive 1080p candidate;
- long-form video;
- unavailable/private fixture through mocked extractor;
- comments-disabled case handled elsewhere.

Live network extraction tests are separate from deterministic merge gates because YouTube changes can break YouTubeKit independently of FocusTube code.
