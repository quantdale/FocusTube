# 13 — Comprehensive Roadmap

The roadmap is gate-driven. Feature count does not advance the project if the underlying viability gate is not proven.

## M0 — Reproducible project and remote Apple CI

**Objective:** a Windows-authored repository can deterministically generate/build/test an iOS app on remote macOS.

Deliverables:

- FocusTubeCore package runs `swift test` on Windows;
- XcodeGen spec generates project on macOS;
- iOS shell builds;
- simulator boots and launches app;
- XCUITest verifies four root tabs;
- CI uploads xcresult/log artifacts;
- toolchain versions logged.

Exit gate: `G0` in `docs/14-ACCEPTANCE-GATES.md`.

## M1 — Media viability proof

**Objective:** prove the riskiest path before broad feature work.

Deliverables:

- `MediaExtracting` protocol;
- YouTubeKit local-only adapter;
- stream normalization into FocusTube-owned models;
- hard quality filter {1080,720,480,360};
- native AVPlayer/AVPlayerViewController playback of extracted long-form video;
- combined-stream background download;
- final-file validation;
- offline playback;
- adaptive 1080p component selection/download/mux proof where source supports it;
- typed error handling;
- live extractor smoke test separated from deterministic suite.

Exit gate: `G1`.

## M2 — Durable download engine

**Objective:** make downloads resilient across interruption/relaunch.

Deliverables:

- actor-based DownloadManager;
- explicit state machine;
- URLSession background task reconciliation;
- pause/cancel/retry policy;
- signed URL re-resolution;
- storage preflight;
- temporary-file cleanup;
- SwiftData DownloadRecord;
- active/completed Downloads UI;
- deterministic transport fixtures.

Exit gate: `G2`.

## M3 — Authentication and YouTube Data API

**Objective:** signed-in account-aware client without coupling media extraction to OAuth.

Deliverables:

- GoogleSignIn integration;
- secure restore of sign-in state;
- minimal required scopes;
- typed YouTubeAPIClient;
- test auth provider;
- subscription list;
- API quota/error handling;
- secrets/config setup documentation.

Exit gate: `G3`.

## M4 — Long-form Home + Shorts firewall

**Objective:** useful daily Home feed that cannot leak short-form discovery.

Deliverables:

- subscription upload aggregation;
- metadata hydration/duration;
- chronological merge;
- ShortFormPolicy applied before rendering;
- explicit paging/load-more;
- pull-to-refresh/cache/staleness policy;
- `/shorts/` deep-link block;
- deterministic feed tests.

Exit gate: `G4`.

## M5 — Search

**Objective:** deliberate search within current quota rules.

Deliverables:

- explicit-submit search;
- local recent query suggestions;
- result hydration;
- duration-based short filtering;
- pagination with quota awareness;
- quota-exhaustion UX;
- search test fixtures.

Exit gate: `G5`.

## M6 — Video detail and comments/account actions

Deliverables:

- production video detail composition;
- comments list/replies pagination;
- post top-level comment;
- post reply;
- subscribe/unsubscribe;
- like/rate where included;
- comments-disabled state;
- download quality sheet with only actual allowed qualities.

Exit gate: `G6`.

## M7 — Local library and continuity

Deliverables:

- local history;
- continue watching/resume;
- local saves;
- downloaded library sorting/filtering;
- storage usage and delete flow;
- SwiftData migrations/reconciliation tests.

Exit gate: `G7`.

## M8 — Background media experience

Deliverables:

- background audio mode;
- AVAudioSession behavior;
- Now Playing metadata;
- MPRemoteCommandCenter play/pause/seek handling;
- PiP;
- interruption handling;
- simulator tests where meaningful.

Exit gate: `G8` plus designated physical-device checks.

## M9 — Hardening campaign

Deliverables:

- full error taxonomy coverage;
- low-storage tests;
- network loss/recovery;
- process termination during download;
- extraction breakage behavior;
- SwiftData migration fixtures;
- accessibility audit;
- performance/memory pass;
- security/log redaction audit;
- no-Shorts regression audit;
- fresh-session agent recovery test.

Exit gate: `G9` release candidate.

## M10 — Personal-device release

Deliverables:

- signing/profile process documented;
- physical iPhone install;
- physical media extraction/playback/download/offline validation;
- PiP/background/lock-screen validation;
- rollback/reinstall/backup expectations documented;
- final checkpoint.

Exit gate: `G10` usable personal release.

## Deferred until after V1

- iPad optimization;
- richer playlist synchronization;
- AirPlay enhancements beyond native support;
- captions/subtitle improvements;
- optional related-video discovery mode;
- richer download scheduling;
- alternate extraction provider (explicitly not planned unless architecture is reconsidered).
