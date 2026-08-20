# 00 — Product Specification

## Purpose

FocusTube converts YouTube from an attention feed into a deliberate video utility. It is built for one primary user and optimized for long-form consumption, offline viewing, and minimal friction without exposing Shorts mechanics.

## Primary jobs

1. Open a chronological feed of recent videos from subscribed channels.
2. Search for a specific video/channel/topic.
3. Watch a selected video in a native player.
4. Download a selected video for offline viewing at one of four allowed resolutions.
5. Read and post comments/replies where the YouTube Data API permits it.
6. Subscribe/unsubscribe, like/rate, and manage supported playlists where practical.
7. Resume partially watched videos locally.
8. Access downloaded media without network connectivity.

## Non-goals

- Rebuild the official YouTube Home recommendation algorithm.
- Rebuild Creator Studio.
- Upload/edit videos.
- Create or browse Shorts.
- Implement a vertical swipe feed.
- Mirror every YouTube social surface.
- Ship to the public App Store as an initial requirement.
- Support Android in V1.
- Support 1440p or 2160p downloads.

## Information architecture

Primary tabs:

- **Home** — chronological/subscription-derived long-form feed.
- **Search** — explicit-submit search; no per-keystroke API search.
- **Downloads** — active queue + completed offline media.
- **Library** — local history, progress, saves, and supported playlists.

Account/settings are accessed from a profile/settings control rather than a fifth primary tab.

## Video detail

A video detail page contains:

- native player;
- title/channel/metadata;
- subscribe state;
- like/save/share actions where supported;
- prominent Download action;
- comments and replies;
- no Shorts carousel;
- no swipe-to-next behavior;
- related videos hidden by default.

## Download policy

Supported video resolutions are exactly:

- 1080p — maximum;
- 720p;
- 480p;
- 360p — minimum normal option.

Rules:

- Show only resolutions actually returned and usable for the selected video.
- Do not manufacture a missing resolution by transcoding.
- Ignore 1440p/2160p and other higher resolutions even if the extractor returns them.
- Default to the highest available member of the allowed set.
- Adaptive streams may download separate video/audio and mux them locally.

## Focus/Shorts policy

FocusTube treats short-form avoidance as a hard product invariant.

- `/shorts/` navigation is blocked.
- No Shorts tab exists.
- No Shorts shelves exist.
- No vertical swipe player exists.
- Home/Search conservatively hide videos with duration <= 180 seconds.
- A blocked short-form URL should produce a non-playable Focus Mode message rather than an override button.
- Autoplay-next is off by default.
- Infinite feed pagination is off by default; explicit "Load more" is preferred.

This policy intentionally permits false positives: a legitimate 2-minute horizontal video may be hidden. Preventing accidental reintroduction of short-form consumption is more important than perfect YouTube classifier parity.

## Offline-first behavior

Downloaded media must remain fully playable without network access. Local metadata and playback progress must not depend on YouTube being reachable.

## Privacy posture

- Personal-use application.
- No analytics SDK by default.
- No ad SDK.
- No third-party telemetry backend.
- OAuth tokens stored using platform-supported secure mechanisms through the sign-in SDK.
- Do not collect more Google/YouTube scopes than required.
