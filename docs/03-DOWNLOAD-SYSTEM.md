# 03 — Download System

## Product invariant

Offline downloading is mandatory. A FocusTube milestone is not viable until a selected allowed-quality video can be downloaded, validated, indexed, and played offline.

## Resolution ladder

Exactly four user-visible qualities exist:

| Quality | Allowed | Notes |
|---|---:|---|
| 1080p | yes | hard maximum; may require adaptive video+audio mux |
| 720p | yes | prefer combined when available |
| 480p | yes | expose only when actually available |
| 360p | yes | minimum standard choice |
| 1440p+ | no | discard |
| <360p | normally no | not shown in normal picker |

Do not transcode to fabricate 480p/720p/etc. If an exact allowed quality is not provided, omit it.

## State machine

Download lifecycle must use one explicit enum/state model:

```text
queued
 -> resolving
 -> downloadingCombined
 -> validating
 -> completed

queued
 -> resolving
 -> downloadingAdaptive(video + audio)
 -> muxing
 -> validating
 -> completed
```

Additional states:

- paused;
- waitingForNetwork;
- retryScheduled;
- needsReResolve;
- failed;
- cancelled.

Transitions must be validated. Impossible transitions should fail loudly in tests.

## Background URLSession

Use `URLSessionConfiguration.background(withIdentifier:)` with a stable bundle-scoped identifier. Foundation delegates transfers to a system process so downloads can continue while the app is suspended/terminated under iOS rules.

Recommended initial settings:

- max concurrent logical downloads: 2;
- cellular downloads: off by default;
- automatic retry for transient failures: up to three attempts total (the initial transfer plus two bounded re-resolution retries — implemented exactly this way by `DownloadRetryPolicy`); every retry re-resolves fresh stream URLs, never replays old ones;
- explicit handling of constrained/expensive networks;
- persist sufficient task metadata to reconcile URLSession tasks after relaunch.

## Expired stream URLs

Treat extracted media URLs as ephemeral.

If a transfer fails with evidence consistent with an expired/invalid signed URL:

1. transition to `needsReResolve`;
2. call MediaExtracting again with the original video ID;
3. select the same requested allowed quality if still available;
4. restart or resume only if byte-range semantics are demonstrably safe;
5. otherwise restart the affected component rather than append corrupt bytes.

## Adaptive 1080p

When 1080p is video-only and audio is separate:

1. choose an allowed/native video stream at exactly 1080;
2. choose best compatible audio-only stream, preferring M4A/AAC where suitable;
3. download both to temporary component files;
4. validate each component;
5. mux using AVMutableComposition/AVAssetExportSession or the most appropriate native AVFoundation export path supported by the target OS;
6. prefer passthrough/remux over transcoding;
7. validate final duration/tracks/readability;
8. atomically move the final file into permanent storage;
9. remove temporary components after the final file is durable.

Do not add FFmpeg unless native muxing is proven insufficient for the exact supported ladder and a new ADR is accepted.

## Filesystem layout

```text
Application Support/
  Media/
    <video-id>/
      media.<container>
      thumbnail.jpg
      metadata.json

Caches/
  Thumbnails/
  Extraction/
  TemporaryMux/
```

Never store final offline media only in Caches or tmp.

Note: the implemented layout is authoritative per accepted ADR-0006 — final media lives at `Media/<video-id>/<quality>/media.<container>` (one subdirectory per quality variant).

## Validation before completed state

A download is `completed` only when:

- final file exists;
- file size is nonzero and plausible;
- AVAsset can load expected tracks;
- video track exists;
- audio track exists for normal video downloads;
- duration is plausible versus metadata;
- AVPlayer can create a playable item in integration tests;
- SwiftData record points to the final relative path.

## Durable queue (DDV2-01)

Capacity-deferred downloads are a durable queue, not a process-memory detail:

- At most two logical downloads are active. Additional requests persist as
  `.queued` SwiftData records carrying planning metadata (`title`,
  `channelTitle`, requested quality, duration) so promotion can be reconstructed
  after process death.
- Queued records never persist signed media URLs — components are empty. Every
  promotion re-resolves fresh streams through `MediaExtracting` at the exact
  originally requested quality.
- Promotion is strictly FIFO by record creation time. New requests may never
  overtake queued work; promoted heads bypass only the sibling-precedence rule,
  never the concurrency bound.
- `.queued` records do not occupy active slots: a stranded queue delays but can
  never permanently deadlock admission.
- Cancelling a queued job deletes its record outright.
- A persisted queued row with an unusable identity/metadata payload degrades to
  the typed `queueStateCorrupted` failure at launch reconciliation — visible,
  actionable, and slot-free.

## Pause/resume limitation

True durable pause/resume is NOT provided. Background `URLSession` download
tasks do not reliably expose resume data across process death, and a pause
control that silently restarts from zero would be dishonest UX. The correct
alternatives shipped instead: cancel (queued or active) and retry, where retry
re-resolves fresh URLs and restarts the affected components cleanly.

## Storage pressure

Before starting a large download, estimate required free space with margin, especially adaptive streams where two components plus final output coexist temporarily. Refuse safely before consuming nearly all device storage.
