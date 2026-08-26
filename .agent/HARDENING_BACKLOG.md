# Hardening Backlog — Deferred During Implementation Campaign

This file is the parking lot for nonblocking Medium/Low quality work discovered while implementing M0–M8. It exists to prevent autonomous agents from spending the implementation campaign polishing indefinitely.

## Rules

- Critical/High correctness, data-integrity, security, secret-leak, build, or no-Shorts regressions are **not** deferred; fix them immediately.
- Medium/Low debt that does not block the active acceptance gate is logged here and implementation continues.
- Do not start a broad hardening sweep during `IMPLEMENTATION_V1` unless the user/state explicitly changes campaign.
- Each item should be specific enough for a later hardening agent to reproduce or inspect.

## Item template

```markdown
### HB-xxx — short title
- Severity: Medium | Low
- Discovered in: WP-xxx / commit
- Area: subsystem/files
- Evidence/reproduction: ...
- Impact: ...
- Suggested hardening action: ...
- Blocks implementation: no
```

## Backlog

### HB-015 — 403 taxonomy conflates every non-commentsDisabled denial with quotaExceeded
- Severity: Medium
- Discovered in: DDV2 systemic-convergence audit (b9ee1e0 era)
- Area: Sources/FocusTubeCore/YouTube/YouTubeDataClient.swift (~:309-325), App copy sites (RootView, VideoPageView)
- Evidence/reproduction: any 403 without the legacy `error.errors[].reason == "commentsDisabled"` envelope maps to `.quotaExceeded`; newer-style `{"error":{"status":"PERMISSION_DENIED"}}` envelopes also fall through; permanent permission denials render the transient "try again later" message.
- Impact: wrong error taxonomy; misleading retry affordances on permanent denials.
- Suggested hardening action: typed `.forbidden` case + reason-string/status mapping, then dedicated UI copy; keep malformed-envelope fallback deliberate.
- Blocks implementation: no

- Resolved 2026-08-26 (HARDENING_V3): implementation + tests landed this campaign; exact evidence and disposition recorded in .agent/work-packets/H3-AUDIT-LEDGER.md.

### HB-016 — all-or-nothing page decoding discards an entire page/batch on one anomalous item
- Severity: Low
- Discovered in: DDV2 systemic-convergence audit
- Area: YouTubeDataClient decode paths (`throw .decode` over whole arrays)
- Evidence/reproduction: one malformed item among 50 fails the whole hydration/feed page (recorded deliberate tradeoff since HB-011a fixtures).
- Impact: full-surface error instead of partial content when Google emits an unexpected shape.
- Suggested hardening action: conscious decision to adopt skip-and-continue per-item decoding with a logged count.
- Blocks implementation: no

- Resolved 2026-08-26 (HARDENING_V3): implementation + tests landed this campaign; exact evidence and disposition recorded in .agent/work-packets/H3-AUDIT-LEDGER.md.

### HB-017 — DownloadState has unreachable statuses and an untested transition table bypassed by event paths
- Severity: Medium
- Discovered in: DDV2 systemic-convergence audit
- Area: Sources/FocusTubeCore/Download/DownloadState.swift; DownloadCoordinator direct status writes
- Evidence/reproduction: nothing ever enters `.waitingForRetry` or `.reResolving`; coordinator assigns `state.status = .failed` directly, bypassing `transition(to:)`; zero transition-table tests exist (only PlaybackState is covered).
- Impact: model drift — the table is advisory; future invalid-transition regressions are undetectable by tests.
- Suggested hardening action: route event-path writes through `transition(to:)` (or delete dead cases after confirming no persisted rows carry them) and add a table test.
- Blocks implementation: no

- Resolved 2026-08-26 (HARDENING_V3): implementation + tests landed this campaign; exact evidence and disposition recorded in .agent/work-packets/H3-AUDIT-LEDGER.md.

### HB-018 — pre-network input validation inconsistent outside comment mutation
- Severity: Low
- Discovered in: DDV2 systemic-convergence audit
- Area: YouTubeDataClient (subscribe/unsubscribe/rate/playlists/comments-read id parameters)
- Evidence/reproduction: empty ids reach the wire and surface as opaque `unknown(status:400)`; comments validate text+parentID first (asymmetric).
- Impact: divergent error taxonomy for garbage input; ids normally originate from API responses so real-world likelihood is low.
- Suggested hardening action: shared non-empty resource-id guard mapped to `.invalidInput`.
- Blocks implementation: no

- Resolved 2026-08-26 (HARDENING_V3): implementation + tests landed this campaign; exact evidence and disposition recorded in .agent/work-packets/H3-AUDIT-LEDGER.md.

### HB-019 — YouTubeAPI protocol-extension defaults convert missing overrides into runtime failures
- Severity: Low
- Discovered in: DDV2 systemic-convergence audit
- Area: Sources/FocusTubeCore/YouTube/YouTubeAPI.swift (eight throwing mutation/lookup defaults)
- Evidence/reproduction: a future conformer omitting an override compiles cleanly and throws `unknown(status:-1)` only when a user taps that action; production client implements all.
- Impact: latent silent-failure mode for new conformers.
- Suggested hardening action: split read vs mutation protocols or drop the defaults.
- Blocks implementation: no

- Resolved 2026-08-26 (HARDENING_V3): implementation + tests landed this campaign; exact evidence and disposition recorded in .agent/work-packets/H3-AUDIT-LEDGER.md.

### HB-020 — OfflineLibraryPolicy stability/tie-order claims exceed language guarantees
- Severity: Low
- Discovered in: DDV2 systemic-convergence audit
- Area: Sources/FocusTubeCore/Library/OfflineLibraryPolicy.swift
- Evidence/reproduction: "Stable: ties preserve input order" relies on incidental stdlib sort behavior; groupedByChannel orders groups via dictionary + max-createdAt so exact-timestamp ties can swap between runs.
- Impact: nondeterministic ordering only in tie cases; personal-scale cosmetic.
- Suggested hardening action: explicit tiebreakers (videoID) and drop/justify the stability claim.
- Blocks implementation: no

- Resolved 2026-08-26 (HARDENING_V3): implementation + tests landed this campaign; exact evidence and disposition recorded in .agent/work-packets/H3-AUDIT-LEDGER.md.

### HB-021 — per-row ISO8601DateFormatter allocation; fractional-second timestamps silently nil
- Severity: Low
- Discovered in: DDV2 systemic-convergence audit
- Area: YouTubeDataClient publishedAt decoding sites
- Evidence/reproduction: formatter constructed inside map per item; RFC3339 fractional forms parse to nil (fields optional everywhere).
- Impact: needless allocation churn; silently missing dates on unusual shapes.
- Suggested hardening action: cached formatters (with/without fractional seconds).
- Blocks implementation: no

- Resolved 2026-08-26 (HARDENING_V3): implementation + tests landed this campaign; exact evidence and disposition recorded in .agent/work-packets/H3-AUDIT-LEDGER.md.

### HB-022 — shared lastFailure alert staleness/presentation ownership
- Severity: Medium
- Discovered in: DDV2 systemic-convergence audit
- Area: App/Download/DownloadService.swift (lastFailure), App/Video/VideoPageView.swift (only presenter)
- Evidence/reproduction: failures raised while Downloads/front-of-house surfaces own settlement (retry, queue promotion, background completion) set lastFailure that nobody displays; the next pushed video page — possibly days later, different video — pops the stale alert.
- Impact: misleading alert context; needs a product decision about where download failures belong (Downloads surface vs global banner).
- Suggested hardening action: present download failures where they originate (Downloads view alert/badge) and clear on presentation; keep video-page alert scoped to its own start attempts.
- Blocks implementation: no

- Resolved 2026-08-26 (HARDENING_V3): implementation + tests landed this campaign; exact evidence and disposition recorded in .agent/work-packets/H3-AUDIT-LEDGER.md.

### HB-023 — Retry path drops durationSeconds, skipping the storage pre-check
- Severity: Medium
- Discovered in: DDV2 systemic-convergence audit
- Area: App/Download/DownloadsView.swift failed-section retry; App/Download/DownloadRecord.swift (no persisted duration for non-queued rows)
- Evidence/reproduction: retry calls download(durationSeconds: 0 default); runOnce documents unknown-duration as skipping the free-space check; queued rows carry duration in QueuedDownloadMetadata but failed rows generally do not.
- Impact: huge-video retry on nearly-full device fails late (finalization/storage) instead of upfront storageRefused.
- Suggested hardening action: additive persisted duration field (lightweight migration) captured at enqueue, threaded through retry.
- Blocks implementation: no

- Resolved 2026-08-26 (HARDENING_V3): implementation + tests landed this campaign; exact evidence and disposition recorded in .agent/work-packets/H3-AUDIT-LEDGER.md.

### HB-024 — download-quality section conflates resolving/failed/empty into one string
- Severity: Low
- Discovered in: DDV2 systemic-convergence audit
- Area: App/Video/VideoPageView.loadQualities; App/Video/DownloadQualityPickerView
- Evidence/reproduction: until extraction finishes (and permanently when extraction fails) the picker reads "No downloadable qualities available" — truthful state is "couldn't check yet/failed".
- Impact: degraded-state distinction collapse; download button correctly disabled either way.
- Suggested hardening action: tri-state picker copy keyed off resolution lifecycle.
- Blocks implementation: no

- Resolved 2026-08-26 (HARDENING_V3): implementation + tests landed this campaign; exact evidence and disposition recorded in .agent/work-packets/H3-AUDIT-LEDGER.md.

### HB-025 — SwiftData save failures are logged-only while UI keeps optimistic state
- Severity: Medium
- Discovered in: DDV2 systemic-convergence audit
- Area: App/Library/LibraryStore.save, App/Search/RecentSearchStore.persist
- Evidence/reproduction: saved/recents flips mutate in-memory state before persistence; a failed save logs a fault but the write silently disappears on relaunch.
- Impact: session-consistent UI that loses data across relaunches with no user-visible signal; needs a product decision on surfacing.
- Suggested hardening action: define a degraded-persistence indicator or write-through verification before mutating UI state.
- Blocks implementation: no

- Resolved 2026-08-26 (HARDENING_V3): implementation + tests landed this campaign; exact evidence and disposition recorded in .agent/work-packets/H3-AUDIT-LEDGER.md.

### HB-026 — composer/reply UX edges beyond the submit-guard fixes
- Severity: Low
- Discovered in: DDV2 systemic-convergence audit (partially fixed b9ee1e0)
- Area: App/Video/VideoPageView.swift composer
- Evidence/reproduction: FIXED in b9ee1e0: duplicate-submit gate before first await, field disabled during flight, posted-text snapshot. Remaining: tapping Reply discards any typed draft without confirmation.
- Impact: occasional input loss requiring retyping.
- Suggested hardening action: preserve draft across reply-target switches or confirm discard.
- Blocks implementation: no

- Resolved 2026-08-26 (HARDENING_V3): implementation + tests landed this campaign; exact evidence and disposition recorded in .agent/work-packets/H3-AUDIT-LEDGER.md.

### HB-027 — main-thread history scans per VideoCard row + per-cell formatter churn
- Severity: Medium
- Discovered in: DDV2 systemic-convergence audit
- Area: App/Components/VideoCard.resumeFraction callers (RootView, SearchView); LibraryStore.history full-table fetch; per-call RelativeDateTimeFormatter/DateFormatter construction
- Evidence/reproduction: N result rows trigger N complete WatchHistoryEntry fetches per body evaluation; every progress tick invalidates observers during playback.
- Impact: correctness holds at personal scale; degradation grows with history size on the main actor.
- Suggested hardening action: inject a precomputed videoID→fraction dictionary per render pass; cache formatters.
- Blocks implementation: no

- Resolved 2026-08-26 (HARDENING_V3): implementation + tests landed this campaign; exact evidence and disposition recorded in .agent/work-packets/H3-AUDIT-LEDGER.md.

### HB-028 — continue-watching strip invisible to VoiceOver on Home/Search cards
- Severity: Low
- Discovered in: DDV2 systemic-convergence audit
- Area: App/Components/VideoCard.swift progress overlay
- Evidence/reproduction: the 4pt strip is decoration with no accessibilityValue; Library rows announce via ProgressView but Home/Search cards do not.
- Impact: VoiceOver users cannot distinguish half-watched from unstarted cards on two of three surfaces.
- Suggested hardening action: expose an accessibilityValue ("x% watched") on the card element without altering the natural-child label composition the journeys assert.
- Blocks implementation: no

- Resolved 2026-08-26 (HARDENING_V3): implementation + tests landed this campaign; exact evidence and disposition recorded in .agent/work-packets/H3-AUDIT-LEDGER.md.

### HB-029 — Low app-UX batch from the convergence audits
- Severity: Low
- Discovered in: DDV2 systemic-convergence audit (b9ee1e0 era)
- Area: multiple views
- Items:
  - AsyncImage with nil legacy thumbnailURL spins forever instead of a failure glyph (VideoCard).
  - Library-reconstructed summaries persist neither channelID nor description, permanently hiding Subscribe and description More/Less when opened from Library/playlists (independent of row age).
  - Playlists load lacks generation token; fast double-tap issues two quota-costing list calls.
  - PlaylistDetailView error state has no retry affordance (siblings all have one).
  - Search submit stays enabled during flight — repeated identical submits burn quota (state safety held by generation guard).
  - Sign-in buttons lack re-entry guards; Settings sign-in silently no-ops under fake sessions.
  - Remaining sub-44pt targets (description More/Less, Reply/Cancel caption buttons) and non-hidden decorative chevrons; watch-history rows lack sibling identifiers/hints.
  - Continue-watching visibility thresholds differ between VideoCard (0.01–0.99) and Library rows (any progress > 0).
  - TabView has no selection binding/state restoration.
  - Share fallback shares file:///? on malformed ids instead of surfacing an error.
- Blocks implementation: no

- Resolved 2026-08-26 (HARDENING_V3): implementation + tests landed this campaign; exact evidence and disposition recorded in .agent/work-packets/H3-AUDIT-LEDGER.md.

### HB-030 — residual deterministic-test gaps
- Severity: Low
- Discovered in: DDV2 systemic-convergence audit
- Area: Tests/FocusTubeCoreTests
- Items: commentThreads pageToken plumbing through the client (playlistItems analog is tested); out-of-range numeric feed-resume index restart; empty-channel-title/negative-size OfflineLibraryPolicy edges; custom maxEntries below existing count for recents; equal-timestamp tie ordering.
- Impact: uncovered edge behaviors only; no known defect behind them today.
- Suggested hardening action: add the listed cheap table cases.
- Blocks implementation: no

- Resolved 2026-08-26 (HARDENING_V3): implementation + tests landed this campaign; exact evidence and disposition recorded in .agent/work-packets/H3-AUDIT-LEDGER.md.

### HB-013 — DownloadsView re-fetches all records on every progress render
- Severity: Low
- Discovered in: FINAL-COMPLETION_V1 audit (2026-08-23)
- Area: App/RootView.swift (DownloadsView), App/Download/DownloadManager.swift (`records`)
- Evidence/reproduction: `records` is a computed SwiftData fetch over all `DownloadRecord`s; `liveTasks` updates on every transport event, so an active transfer re-runs the fetch per render.
- Impact: bounded overhead (personal-scale record counts); no correctness effect.
- Suggested hardening action: cache a filtered failed-tasks projection updated from event application.
- Blocks implementation: no
- Resolved 2026-08-24 (SPEC_CLOSURE_DAILY_DRIVER_V2): DownloadManager now
  maintains cached projections (`queuedTasks`, `failedTasks`) updated at
  mutation points (applyLive/syncRecord/cancel/reconcile/delete) instead of
  per-render fetches; presentation-metadata lookups are memoized in a
  metadataCache; DownloadsView renders from the projections.

### HB-014 — Fixture video pages intentionally show the bounded "Playback failed" overlay
- Severity: Low
- Discovered in: FINAL-COMPLETION_V1 campaign (run #118 diagnostics)
- Area: FocusTubeUITests fixtures; App/Playback/PlayerView.swift
- Evidence/reproduction: fixture stream URLs are non-resolvable hosts, so AVPlayerItem legitimately reaches `.failed`; journeys assert around the overlay.
- Impact: none for production; future journeys that need a *playing* state need a local file:// fixture stream.
- Suggested hardening action: add a tiny bundled media asset to the fixture harness if playback-state journeys become necessary.
- Blocks implementation: no
- Resolved 2026-08-24 (SPEC_CLOSURE_DAILY_DRIVER_V2): FixtureMediaFactory
  generates a tiny genuinely decodable H.264 MP4 at runtime inside the DEBUG
  fixture harness (no committed binaries); ScriptedDownloadTransport finalizes
  real playable media, DownloadsView presents a visible local player sheet,
  PlayerView exposes a `.playing`-only marker, and journey L asserts genuine
  offline playing state.

### HB-001 — VideoPageView registers onProgress after loadAndPlay
- Severity: Low
- Discovered in: INTEGRATION_COMPLETION_V1 audit (cba7e67 era)
- Area: App/Video/VideoPageView.swift
- Evidence/reproduction: `coordinator.onProgress = ...` is assigned after `await coordinator.loadAndPlay(...)` returns; progress callbacks fired during early playback setup are missed.
- Impact: first moments of playback progress may not render.
- Suggested hardening action: register the callback before calling loadAndPlay.
- Blocks implementation: no
- Resolved 2026-08-21: VideoPageView registers onProgress and Now Playing metadata before loadAndPlay.

### HB-002 — reattached downloads restart progress aggregation at zero
- Severity: Low
- Discovered in: reattachment slice (0a0683f)
- Area: App/Download/BackgroundDownloadTransport.swift, App/Download/DownloadManager.swift
- Evidence/reproduction: after relaunch reattachment, byte counts are not seeded from the persisted record; UI progress restarts from 0 until the next cumulative didWriteData event.
- Impact: cosmetic progress regression after relaunch; correctness unaffected (URLSession totals are cumulative).
- Suggested hardening action: seed componentProgress from the persisted record on attach.
- Blocks implementation: no
- Resolved 2026-08-21: reconcileOnLaunch seeds the reattached task's cumulative progress from the persisted record (coordinator.seedProgress) and republishes the live snapshot.

### HB-003 — tiny event window between reattach registration and coordinator attach
- Severity: Low
- Discovered in: reattachment slice (0a0683f)
- Area: App/Download/DownloadManager.swift reconcileOnLaunch
- Evidence/reproduction: a .completed delegate event landing between transport handler registration and coordinator.attach is dropped; that transfer would sit .downloading until next retry.
- Impact: rare stuck record after a precisely-timed relaunch.
- Suggested hardening action: buffer early events in the transport or re-check task states after attach.
- Blocks implementation: no
- Resolved 2026-08-21: reattached events are routed through a main-actor buffer during reconciliation and replayed in arrival order once their request attaches; post-reconcile events pass straight through as before.

### HB-004 — stale-response race in SearchStore/HomeFeedStore loads
- Severity: Medium
- Discovered in: HARDENING_V1 audit (dd5d648 era)
- Area: App/Search/SearchStore.swift, App/Home/HomeFeedStore.swift
- Evidence/reproduction: concurrent submit/load calls are not serialized; last response wins and can regress visible state.
- Impact: observable state may briefly show older results.
- Suggested hardening action: generation token or task cancellation per load.
- Blocks implementation: no
- Resolved 2026-08-21: monotonic loadGeneration in both stores; superseded responses no longer mutate results/error, and isLoading ownership follows the newest load.

### HB-005 — Now Playing metadata never published
- Severity: Medium
- Discovered in: HARDENING_V1 audit
- Area: App/Media/BackgroundMediaCoordinator.swift (updateNowPlaying has no call sites)
- Impact: lock screen shows no title/artwork/duration though remote commands work.
- Suggested hardening action: publish via NowPlayingInfoBuilder on playback state changes/progress ticks.
- Blocks implementation: no
- Resolved 2026-08-21: PlayerCoordinator exposes nowPlayingSnapshot + onNowPlayingChanged (item change, state transitions, 5s progress ticks); BackgroundMediaCoordinator.publishNowPlaying writes/clears MPNowPlayingInfoCenter; wired in RootView.

### HB-006 — per-event unstructured Tasks allow event reordering
- Severity: Medium
- Discovered in: HARDENING_V1 audit
- Area: Sources/FocusTubeCore/Download/DownloadCoordinator.swift begin(onEvent:), App/Download/DownloadManager.swift reattach handler
- Impact: a late progress/completed Task can overtake a failed event; benign today because transitions guard, but ordering is not guaranteed.
- Suggested hardening action: serialize events per task (AsyncStream mailbox).
- Blocks implementation: no
- Resolved 2026-08-21: DownloadCoordinator.handle chains each event's processing Task onto the previous one per taskID, so events apply strictly in arrival order; begin()'s onUpdate fires from the serialized path, and chains reset on enqueue/cancel.

### HB-007 — RootView.init side effects run on every struct evaluation
- Severity: Medium
- Discovered in: HARDENING_V1 audit
- Area: App/RootView.swift init, App/Download/DownloadManager.swift init-spawned reconcile Task
- Impact: discarded instances still open containers/spawn reconciliation.
- Suggested hardening action: hoist dependencies into a single container created in FocusTubeApp.
- Blocks implementation: no
- Resolved 2026-08-21: AppDependencies (@MainActor) owns container/stores/coordinator creation and wiring; FocusTubeApp holds it in @State and RootView consumes it, so struct re-evaluation no longer opens containers or spawns reconciliation.

### HB-008 — waitForCompletion polls up to 10 min and ignores cancellation
- Severity: Medium
- Discovered in: HARDENING_V1 audit
- Area: App/Download/DownloadManager.swift waitForCompletion
- Impact: dismissed views keep polling; timeout reports failure while transfer continues (late completion then registers media — user saw a false failure).
- Suggested hardening action: checkCancellation per iteration + event-driven continuation; distinguish timed-out-but-active from settled failure.
- Blocks implementation: no
- Resolved 2026-08-21: waitForCompletion throws CancellationError on task cancellation and returns the still-active task on timeout; DownloadService treats active-on-timeout as non-failure (transfer continues, record settles via events).

### HB-009 — storage admission floor never enforced
- Severity: Medium
- Discovered in: HARDENING_V1 audit
- Area: App/Download/DownloadService.swift (requiredBytes always 0), docs/03 storage rule
- Impact: full device drives cryptic finalization/mux failures instead of typed storageRefused.
- Suggested hardening action: enforce free-space floor before begin, or expose stream byte sizes for real estimates.
- Blocks implementation: no
- Resolved 2026-08-21: StorageEstimator (Core) computes conservative requiredBytes from duration+tier with adaptive headroom; DownloadService passes it to enqueue so storageRefused precedes any partial work.

### HB-010 — final validation is existence+size only
- Severity: Medium
- Discovered in: HARDENING_V1 audit
- Area: Sources/FocusTubeCore/Download/DownloadCoordinator.swift finalize
- Impact: truncated-but-nonempty files register as completed.
- Suggested hardening action: injected AVFoundation asset-validator seam at app layer.
- Blocks implementation: no
- Resolved 2026-08-21: DownloadCoordinator accepts an injected validate seam run on the finalized file; the app supplies AVFoundation track validation (MediaAssetValidator) and failing files are discarded as .validationFailed.

### HB-011 — test gaps: malformed payloads per endpoint, store error paths, comments-disabled detection
- Severity: Medium
- Discovered in: HARDENING_V1 audit
- Area: Tests/FocusTubeCoreTests, FocusTubeTests
- Suggested hardening action: table-driven malformed-JSON cases per endpoint; SearchStore/HomeFeedStore deterministic error tests incl. 401; commentsDisabled 403-envelope fixture.
- Blocks implementation: no
- Resolved 2026-08-22 (commit 03ce6f6): table-driven malformed-payload coverage for all five decoding endpoints of YouTubeDataClient (truncated / wrong-typed / missing-field / wrong-envelope) plus malformed 403 error-body fallback-to-status mapping and the commentsDisabled 403 envelope driven through CommentsService with a quota-reason negative control (YouTubeDataClientTests). New deterministic SearchStoreTests (5) and HomeFeedStoreTests (3): typed error surfacing, spinner settling, auth-class failures retaining prior content, and generation-guard stale-response protection via park-and-release CallGate fakes with hard arrival deadlines.

### HB-012 — Low batch
- Severity: Low
- Items: transport-held closures retain coordinator until terminal event; removeTarget(nil) blast radius; PlayerCoordinator deinit teardown assumption; in-memory fallback try!; duplicate extraction per video page + unordered history writes; muxing-* orphan sweep at launch; DownloadRecord components decode-failure silent no-op retry; try? context.save() silent failures; VolumeStorage 0-on-error ambiguity; empty Media/<id>/<quality>/ dirs never pruned; layout divergence Media/<videoID>/<quality>/ vs spec Media/<videoID>/media.<container> (multi-quality justification noted, ADR line pending).
- Blocks implementation: no
- Partially resolved 2026-08-21: `.muxing-*` orphan sweep implemented in reconcileOnLaunch (DownloadManager.sweepMuxingOrphans); layout divergence resolved by accepted ADR-0006 (per-quality layout is authoritative); empty Media/<id>/<quality>/ dirs pruned on delete/reconcile; silent context.save() failures now log via os.Logger in LibraryStore/DownloadManager; VolumeStorage logs failed capacity queries; duplicate per-page extraction removed (PlayerCoordinator.lastResolvedMedia reused by the video page's quality picker). History-write ordering intentionally left last-write-wins: a value-monotonic guard would break persisting legitimate manual rewinds, and the per-tick reorder window is bounded by the 5s observer cadence.
- Resolved 2026-08-22 (commit 03ce6f6): remaining sub-items closed. Transport-held closures no longer retain the coordinator ([weak self] in DownloadCoordinator.begin) and per-event unstructured Tasks were replaced with lock-guarded completion-node chains that preserve strict arrival order (regression-tested in DownloadCoordinatorEventOrderingTests). BackgroundMediaCoordinator re-registration removes only its own addTarget tokens instead of removeTarget(nil). AppDependencies in-memory ModelContainer fallback no longer try!s (logged fault + do/catch ladder, fatal last resort with context). DownloadRecord components decode failures log via os.Logger and never emit payload bytes. PlayerCoordinator deinit teardown assumption stands as documented: the instance lives for the app lifetime under AppDependencies ownership, so no teardown path exists to get wrong.

### HB-031 — subscription feed playlist walk is strictly sequential across playlists
- Severity: Low
- Discovered in: 2026-08-26 optimization campaign (owner directive)
- Area: Sources/FocusTubeCore/YouTube/YouTubeAPI.swift default `fetchSubscriptionFeed`
- Evidence/reproduction: the playlistItems walk visits subscriptions one at a time (up to two pages each) before pausing at the continuation point; with many subscriptions this serializes N×(1..2) round trips before any content renders.
- Impact: cold-start latency scales linearly with subscription count; detail-hydration batches are ALREADY concurrent (this campaign), so the walk is now the remaining serial segment.
- Suggested hardening action: deliberately NOT taken — the pause-point semantics ARE the quota-bounding design (a concurrent walk would fetch pages beyond the pause point and consume extra quota units per load). Redesigning it is a product/quota-policy decision that needs an explicit directive plus a redesigned continuation contract, not a mechanical optimization.
- Blocks implementation: no

### HB-032 — waitForCompletion polls the coordinator every 500 ms
- Severity: Low
- Discovered in: 2026-08-26 optimization campaign (owner directive)
- Area: App/Download/DownloadManager.swift waitForCompletion
- Evidence/reproduction: the settle wait loops on a 500 ms sleep + coordinator.task(id) actor hop until terminal state or the 600 s timeout.
- Impact: bounded idle wakeups (≤4/s per transferring job, ≤2 jobs) — negligible CPU, but an event-driven continuation keyed off the existing onTaskSettled path would eliminate them entirely.
- Suggested hardening action: replace polling with per-task continuations resumed from applyLive/cancel settlement points, keeping the current CancellationError and timeout-return-current-task contracts; requires careful re-proof of the durability-sensitive settle cluster, so deferred as low value-at-risk.
- Blocks implementation: no