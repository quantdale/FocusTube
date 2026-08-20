# 13 — Comprehensive Roadmap

FocusTube uses **campaigns, milestones, work packets, and evidence gates**. Feature count does not advance state; observed acceptance evidence does.

## Campaign model

### Active now — IMPLEMENTATION_V1

Scope: **M0 through M8**, packets **WP-000 through WP-011**.

Goal: implement the complete V1 architecture and product surface to automated build/test/simulator-complete status with no Critical/High known regressions.

The implementation agent runs continuously through this sequence and does not stop between packets.

### Later — HARDENING

Scope: M9 and `.agent/HARDENING_BACKLOG.md` plus newly discovered torture/a11y/performance/security issues.

Broad hardening is deliberately postponed so the implementation campaign does not become an endless cleanup loop. Critical/High defects remain immediate blockers and are never deferred.

### Later — PERSONAL_RELEASE

Scope: M10, signing/install and physical-iPhone evidence.

Device-only verification does not block the current implementation campaign.

---

## Current status as of 2026-08-20

- Bootstrap repository/specification scaffold exists on `main` at commit `81384e84127177186eaa9f87f71a36874f47b785`.
- `FocusTubeCore` has observed passing policy tests in the artifact-construction environment.
- G0 is **not yet proven** because macOS/XcodeGen/iOS Simulator CI evidence has not been observed.
- Current implementation packet: `WP-000-BOOTSTRAP`.
- No media extraction/playback/download viability gate is yet claimed complete.

Always trust `.agent/STATE.yaml` over this dated narrative if implementation has advanced.

---

# IMPLEMENTATION_V1 roadmap

## M0 — Bootstrap / reproducible Apple build plane

**Why first:** every iOS-specific packet depends on a reliable remote Mac/Xcode/Simulator loop because the primary authoring host is Windows.

Deliver:

- Windows/platform-neutral `swift test` path;
- XcodeGen project generation on macOS;
- package resolution for pinned dependencies;
- iOS shell build;
- dynamic selection/boot of an available iPhone Simulator;
- app install/launch;
- root-tab XCUITest;
- xcresult/log/screenshot artifacts and toolchain-version evidence.

Do not spend time on: production UI styling, auth, feed design.

Exit: **G0**. Immediately advance to WP-001.

## M1 — Media viability

Packets: WP-001 through WP-004.

**Why second:** if local YouTubeKit extraction + native playback + offline download + adaptive 1080 mux cannot be made viable, the product architecture must be revisited before building the rest.

Deliver in risk order:

1. `MediaExtracting` and YouTubeKit local-only adapter;
2. FocusTube-owned normalized stream models;
3. hard allowed-quality filtering `{1080,720,480,360}`;
4. AVPlayer/AVPlayerViewController online playback;
5. combined-stream background download;
6. atomic final-file validation/offline playback;
7. separate 1080p video+audio component download;
8. native AVFoundation mux/export proof;
9. typed extraction/playback/download errors;
10. deterministic fake-extractor suite + isolated live smoke suite.

Do not spend time on: polished Home/Search/comments/library.

Exit: **G1**.

## M2 — Durable download engine

Packet: WP-005.

Goal: convert the viability download path into a recoverable subsystem suitable for real daily use.

Deliver:

- actor-owned DownloadManager;
- explicit states/transitions;
- background URLSession task reconciliation;
- pause/cancel/retry semantics where platform-supported;
- signed-URL re-resolution;
- storage preflight;
- temp-file lifecycle/cleanup;
- SwiftData DownloadRecord persistence;
- file/metadata reconciliation;
- active/completed Downloads UI;
- deterministic transport/test fixtures.

Exit: **G2**.

## M3 — Authentication + typed YouTube Data API

Packet: WP-006.

Deliver:

- GoogleSignIn adapter and safe restore flow;
- minimum scopes required by supported actions;
- fake-auth provider for routine automation;
- typed URLSession YouTubeAPIClient;
- request/response/error/quota models;
- subscription-list integration;
- secret/log redaction guarantees;
- configuration docs that keep credentials out of source control.

Real OAuth evidence may require safe user/project configuration; lack of credentials does not prevent deterministic implementation from proceeding.

Exit: **G3**.

## M4 — Long-form Home + Shorts firewall

Packet: WP-007.

Deliver:

- subscription upload aggregation;
- metadata hydration/duration;
- chronological merge;
- caching/staleness policy;
- ShortFormPolicy applied **before render**;
- explicit `Load more`, never implicit infinite scroll;
- `/shorts/` deep-link rejection;
- deterministic no-leak regression tests.

Exit: **G4**.

## M5 — Deliberate search

Packet: WP-008.

Deliver:

- remote search only on explicit submit;
- local recent-query suggestions;
- hydration/duration lookup;
- short-form filtering before render;
- quota-aware pagination;
- quota-exhaustion/error UX;
- deterministic search fixtures.

Exit: **G5**.

## M6 — Video detail / comments / supported account actions

Packet: WP-009.

Deliver:

- production video detail composition around native player;
- comments/read/replies pagination;
- comments-disabled state;
- post top-level comment and reply;
- subscribe/unsubscribe;
- selected supported rating/like behavior when enabled by API design;
- download sheet exposing only available allowed qualities;
- coherent loading/error/optimistic-state behavior.

Exit: **G6**.

## M7 — Local library + continuity

Packet: WP-010.

Deliver:

- watch history local to FocusTube;
- resume/continue-watching state;
- local saves;
- downloaded library sort/filter;
- storage usage/delete flow;
- SwiftData migration/reconciliation tests;
- useful offline behavior without depending on YouTube history access.

Exit: **G7**.

## M8 — Background media integration

Packet: WP-011.

Deliver:

- audio-session setup;
- background-audio capability/config;
- Now Playing metadata;
- MPRemoteCommandCenter play/pause/seek integration;
- PiP wiring;
- interruption/route-change handling;
- automated tests/simulator smoke where the platform meaningfully supports them;
- explicit list of device-only evidence deferred to release.

Exit: **G8**, then run **IC-EXIT** integration-completion gate.

---

# IC-EXIT — Implementation campaign completion

Before marking implementation complete, run a cross-feature automated sweep proving:

- app/project generation/build remains reproducible;
- deterministic suite is green;
- simulator app launches and core navigation works;
- extraction adapter boundaries remain local-only;
- download ladder is still exactly 1080/720/480/360;
- no Shorts surface/route/vertical swipe path exists;
- download/offline/library flows integrate without known Critical/High defect;
- auth/API uses deterministic test seams and no secrets are committed;
- background-media implementation builds and device-only checks are documented;
- durable state/checkpoints are coherent enough for a fresh agent to recover.

When IC-EXIT passes set:

```text
status = implementation_complete_ready_for_hardening
campaign IMPLEMENTATION_V1 = complete
```

Do not automatically launch the broad hardening campaign.

---

# Later campaigns

## M9 — Hardening

Use `.agent/HARDENING_BACKLOG.md` plus full error taxonomy, network loss/recovery, process termination, low storage, extraction breakage behavior, persistence migration, accessibility, performance/memory, security/log redaction, no-Shorts regression, and fresh-session recovery audits.

Exit: G9 release candidate.

## M10 — Personal-device release

Perform signing/profile setup, physical iPhone install, real extraction/playback/download/offline validation, quality-ladder checks, PiP/background/lock-screen verification, and document limitations/recovery.

Exit: G10 personal release.

## Deferred beyond V1

- iPad-specific optimization;
- richer playlist synchronization;
- richer captions/subtitle work;
- discovery/recommendation modes beyond intentional product scope;
- alternate extractor/provider architecture;
- backend/cloud sync not required by V1.