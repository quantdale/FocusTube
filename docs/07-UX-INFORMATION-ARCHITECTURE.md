# 07 — UX and Information Architecture

## Design principles

1. One selected video is one discrete activity.
2. Deliberate actions beat algorithmic nudges.
3. Downloading is prominent, not buried.
4. Offline state is obvious.
5. Short-form mechanics are absent rather than merely hidden behind settings.
6. System-native media controls are preferred over custom ornamental controls.

## Home

- chronological or recent subscription-driven feed;
- video cards show thumbnail, title, channel, publish time, duration;
- duration is known before eligibility is decided;
- blocked short-form entries never render;
- page in explicit chunks (initial target 20) with a Load More control;
- pull-to-refresh supported;
- no Shorts shelf.

## Search

- query field;
- explicit Search submit;
- local recent-query suggestions may update per keystroke;
- remote YouTube search does not run per keystroke;
- hydrate video duration then apply Focus policy before display.

## Video

- native AVPlayerViewController presentation embedded or fullscreen as appropriate;
- title/channel/action row;
- Download action opens exact available allowed resolutions;
- comments below;
- related videos off by default;
- no swipe gesture mapped to next media.

## Downloads

Two clear sections:

- Active: queue/progress/retry/pause/cancel;
- Offline: completed videos sortable by date/size/channel.

Each completed item can play with no network.

## Library

- local watch history;
- continue watching;
- local saves;
- supported YouTube playlists when authenticated;
- storage management.

## Accessibility

Use native controls, semantic labels/identifiers, Dynamic Type where practical, VoiceOver labels, minimum hit sizes, and meaningful state descriptions. XCUITest identifiers are part of the implementation contract, not post-hoc QA glue.
