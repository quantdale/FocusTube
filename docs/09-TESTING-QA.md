# 09 — Testing and QA Strategy

## Principle

Most application behavior must be deterministic and testable without live Google credentials or live YouTube. Live extraction is a separate smoke layer.

## Test pyramid

### Tier 0 — Windows core tests

Run `swift test` for FocusTubeCore on every local agent iteration touching domain behavior.

Cover:

- quality ladder;
- ShortFormPolicy;
- feed merge/filter/order;
- download state transitions;
- retry decisions;
- quota/search policy;
- parser behavior;
- storage estimates.

### Tier 1 — macOS/iOS unit + integration tests

Use XCTest/Swift Testing on macOS runner for adapters with fakes:

- API decoding;
- persistence;
- media file store;
- mocked extractor selection;
- mocked background-download reconciliation;
- mux validation fixtures where feasible.

### Tier 2 — XCUITest simulator tests

Automate real UI flows against deterministic fixture providers:

- launch;
- Home tabs/navigation;
- feed rendering;
- blocked short removal;
- search submit;
- video screen;
- comments states;
- download picker with exactly allowed available qualities;
- download progress/completed state using fixture transport;
- offline library navigation.

Every important control receives a stable accessibility identifier.

## iOS 26 simulator notes (learned 2026-08-23, run #115–#120)

- Modal `.sheet` presentation of AVKit-hosting content never exposed its
  content to the accessibility hierarchy on current iOS 26 runtimes; the
  video page is therefore a **pushed** `navigationDestination` route, which
  exposes correctly and is also better navigation semantics.
- SwiftUI `List` lazily materializes rows near the viewport only —
  below-the-fold controls do not exist for XCUITest until scrolled into
  view. Journeys scroll elements into the lazy hierarchy before asserting.
- Alert message copy may live outside the alert's `staticTexts` subtree;
  assert typed failure copy app-wide.
- Player overlay states must be hard-bounded inside List rows: flexible
  `maxHeight` frames inflate the row and push later sections below the lazy
  fold.

### Tier 3 — live YouTubeKit smoke

Small network-dependent suite, separate from deterministic merge gate:

- extraction returns at least one allowed stream for known public long-form sample;
- 1080p adaptive case when sample remains suitable;
- selected URLs are readable/playable enough to begin AVAsset loading;
- error is typed when extraction fails.

A live failure may indicate upstream YouTubeKit/YouTube change rather than a FocusTube regression. Investigate before changing app architecture.

### Tier 4 — physical iPhone milestone tests

Manual-minimal but mandatory at designated gates. Record date/device/iOS/build and pass/fail evidence in `.agent/checkpoints/`.

## Visual artifacts

CI simulator tests should capture screenshots for at least:

- root Home;
- Search;
- Video detail;
- Download quality sheet;
- Active Downloads;
- Offline Library;
- Focus-blocked state.

Store as workflow artifacts, not committed binaries.

## Regression severity

Critical:

- data loss/corruption;
- secret leakage;
- wrong media file associated with video;
- app cannot launch;
- short-form vertical consumption introduced.

High:

- download/offline playback broken;
- Shorts filter leaks clearly blocked items;
- OAuth/account writes target wrong resource;
- background task reconciliation corrupts state.

Critical/High block milestone completion.
