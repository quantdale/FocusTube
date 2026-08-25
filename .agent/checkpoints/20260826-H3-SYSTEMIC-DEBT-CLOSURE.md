# Checkpoint — HARDENING_V3 Systemic Debt Closure (H3)

Date: 2026-08-25/26 (Windows-authoring session, single coordinator)
Campaign packet: `.agent/work-packets/H3-CAMPAIGN.md`
Audit ledger: `.agent/work-packets/H3-AUDIT-LEDGER.md`
Execution prompt: `.agent/EXECUTION_PROMPT.md` → marked `Status: COMPLETE` by this checkpoint.

## Session identity

- Start: resumed at local HEAD `01e1eeb`; fetched and fast-forwarded `01e1eeb..a581f38`
  (four planning commits that activated HARDENING_V3).
- Repository: quantdale/FocusTube, branch main; worktree stayed clean between waves.
- gh CLI unauthenticated on this host (re-verified) — live-smoke dispatch remains owner-gated.

## Starting truth

- Code qualification baseline entering H3: `05a80af` (DDV2 exit; Core Tests 32855544250 /
  iOS CI 32855544105 SUCCESS).
- Local matrix at open: swift build clean; swift test 118 XCTest + 11 swift-testing, 0 failures.
- All 16 backlog items HB-015..HB-030 verified LIVE against code before any edit
  (ledger §Ledger), with implementation sites/callers/tests/migration implications recorded.

## Work performed (waves, commits, validation)

1. H3-00 (`4611464`, docs) — ledger + STATE/WAYPOINTS transitioned to HARDENING_V3;
   hosted Core Tests run 32863980246 SUCCESS at a581f38 observed before edits.
2. H3-01 (`80e5279`) — API hardening:
   - Typed 403 taxonomy: new `.forbidden` case; legacy reason family + canonical
     RESOURCE_EXHAUSTED / PERMISSION_DENIED statuses mapped; commentsDisabled precedence
     kept; deliberate quota fallback for opaque bodies (rationale in client + ledger).
     Five UI error-label sites gained explicit non-retry copy.
   - Tolerant item decoding with two truthfulness bounds (all-malformed ⇒ .decode;
     partial skips reported through injected observer wired to os.Logger); top-level
     envelopes stay strict.
   - Shared pre-wire resource-id validation (.invalidInput) across 12 call shapes,
     no-network table-tested.
   - Protocol decomposition YouTubeReading/YouTubeWriting (+ YouTubeAPI typealias);
     all eight throwing defaults removed; FullStubAPI proven trap-dependent and fixed.
   - Cached thread-safe RFC3339 parsers incl. fractional seconds.
   - commentThreads pageToken plumbing + out-of-range feed resume index pinned.
3. H3-02 (`ba67685`) + CI repair (`ec1f7a3`):
   - Dead statuses removed; every coordinator event write routes through legal
     transitions; settled completion is FINAL vs late failures (EventOrdering test
     rewritten to assert the strengthened contract, not weakened).
   - Failure ownership: lastFailure only for user-requested starts; promotion failures
     present as failed rows (app-target tests added).
   - plannedDurationSeconds additive persistence threaded through retry storage admission.
   - Build-break root causes from annotations of run 32869064329/32873103739:
     labeled ModelContext init that does not exist repo-wide, and a @MainActor reporter
     failing @Sendable conversion — plus missing `import os` in DownloadService
     (annotation of run 32873103739, fixed in d8de31f).
4. H3-03 (`d8de31f`) — OfflineLibraryPolicy total deterministic ordering (id tiebreakers,
   grouping ties); two-tier truthful persistence (rollback for durability-critical index,
   degraded flag for session-tolerant data, write-through recents) behind an injected save
   seam with failure-injection tests; navigation-origin metadata fidelity across
   playlistItems decode → PlaylistItemSummary additive optionals → PlaylistDetailView /
   RootView reconstruction, backed by additive WatchHistoryEntry/SavedItem fields.
5. H3-04+H3-05 (`989f4af`) — resumeFractions() single-fetch memoized projection replacing
   per-card full-history scans (Home/Search); cached card formatter; tri-state quality
   lifecycle; per-target composer drafts; card progress accessibilityValue; nil-thumbnail
   bounded glyph; playlists/detail duplicate-load guards + real retry affordance;
   identical in-flight search submit gate; sign-in re-entry guards + truthful fake-session
   notice; 44pt caption targets; AX-hidden chevrons; SceneStorage tab selection; controlled
   malformed-share alert.
6. H3-06 (`2087737`) — final HB-030 gap: custom-cap trimming table test.
7. H3-07 (`d054070`) — whole-repository re-audit documented (ledger §H3-07): 15 checklist
   areas inspected with observed evidence; no Critical/High residual; two Low notes
   recorded (recents load cap artifact; zero-fraction boundary cosmetic).

Local matrix after all waves: swift build clean; swift test 141 XCTest + 11 swift-testing,
0 failures (139→141 across H3-04/H3-06 additions). Final local verification at 7a70943
tree: 141+11, zero failures.

## Qualification evidence (H3-08)

- Final CODE SHA of the campaign: `7a70943`.
- Core Tests at 7a70943: run 32891558919 SUCCESS (workflow-list observed).
- iOS CI fail-closed Gate at 7a70943: run 32891558884 (run #196) SUCCESS — Build Debug ✓,
  Build Release ✓, Unit ✓ (141 XCTest incl. the corrected ownership test), UI journeys
  20/20 TEST SUCCEEDED, Gate contract self-check ✓, Gate genuinely green.
- Consecutive-leg policy (broad UI campaign): second leg taken on the docs
  reconciliation tip per DDV2 precedent — result appended below after observation.

### Red-leg root causes encountered during qualification (truthful record)

- 80e5279 / ec1f7a3 legs: app-target compile breaks — nonexistent labeled ModelContext
  init; @MainActor reporter reference not convertible to @Sendable closure
  (annotations of runs 32869064329 / 32873103739); missing `import os` in
  DownloadService surfaced next leg; fixed in ba67685..d8de31f.
- #191 (989f4af): Swift 6 rejected isolated fn reference over Comment
  (`replyTarget.map(Self.draftKey(for:))`) — fixed 8b8345d.
- #192/#193/#194 legs: ownership fixture DEADLOCKED ITSELF — `await
  service.download(v1)` blocks until settlement while v1 was gated by a later
  line, riding into the 180s execution allowance and dying WITHOUT an assert
  line (why three legs showed only the test name). Additionally completion events
  pointed at nonexistent temp paths until staged REAL bytes. Fixed via per-
  download tasks + queuedTasks-sequenced deferral (7a70943). Diagnostics
  hardening added full failed-case context to annotations (aa42207) and is kept.

## Durable-state reconciliation performed at exit

- STATE.yaml → hardening_v3_complete_device_validation_pending; waypoint
  DEVICE_VALIDATION_V1_REFRESHED with refreshed baseline 7a70943; resume token updated.
- WAYPOINTS.yaml → H3-01..H3-EXIT complete with observed evidence lines.
- HARDENING_BACKLOG.md → every HB-015..HB-030 carries a Resolved record pointing at
  the ledger; no contradictory open-debt prose remains.
- EXECUTION_PROMPT.md → Status: COMPLETE with terminal summary header.
- work-packets/INDEX.md unchanged (already authoritative for H3 ordering).

## Remaining external owner-only evidence (unchanged, never fabricated)

- Physical-iPhone DEVICE_VALIDATION Batch A A1-A14 against refreshed baseline 7a70943.
- One authenticated opt-in live_smoke dispatch (gh unauthenticated on this host).
- Real-device PiP/background/lock-screen/Bluetooth behavior.
- Real-device PiP/background/lock-screen/Bluetooth behavior.

## Consecutive-leg evidence (appended after the docs-tip leg completed)

- Docs-tip iOS CI run: RESULT_RECORDED_BELOW.
