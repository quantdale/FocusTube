# 16 — Autonomous Implementation Campaign Playbook

This document defines **how** to execute M0–M8 continuously. Product behavior remains governed by the subsystem specs.

## Campaign objective

Reach a code-complete, automated-testable V1 implementation with the riskiest external/media path proven early, durable downloads/account/feed/search/comments/library/background-media implemented, no known Critical/High defect, and sufficient state/evidence for a later independent hardening campaign.

## Campaign anti-goals

Do not spend the active campaign on:

- broad visual redesign/polish unrelated to acceptance;
- generalized architecture for hypothetical V2 features;
- exhaustive a11y/performance/torture work beyond what blocks correctness;
- alternate extractors/backends;
- iPad-specific optimization;
- physical-device-only validation when no device is available;
- cleaning every warning/TODO merely because it exists.

Log nonblocking hardening work and continue.

## Execution order

```text
WP-000  Bootstrap remote Apple loop
   |
WP-001  Local extraction adapter
   |
WP-002  Native online playback
   |
WP-003  Combined download + offline playback
   |
WP-004  Adaptive 1080 + native mux
   |
WP-005  Durable download manager
   |
WP-006  Auth + Data API
   |
WP-007  Home + Shorts firewall
   |
WP-008  Search
   |
WP-009  Video/comments/actions
   |
WP-010  Library/continuity
   |
WP-011  Background media
   |
IC-EXIT -> implementation_complete_ready_for_hardening
```

This sequence intentionally front-loads the highest existential technical risks.

## Packet implementation rhythm

For every packet:

### A. Reconnaissance

- confirm dependencies/gate status;
- inspect relevant protocols/models/tests/current implementation;
- identify the smallest acceptance criterion not yet proven;
- identify deterministic and Apple/live validation required.

### B. Build a vertical slice

Prefer a thin complete path over many disconnected stubs. For example, in download work prefer one real `queued -> resolving -> downloading -> validating -> completed` path over building all screens before transport works.

### C. Test close to the behavior

- pure policy/state -> FocusTubeCore unit tests;
- external adapter -> deterministic fake + adapter tests;
- iOS framework integration -> macOS build/unit/UI tests;
- UI/navigation -> XCUITest/fixture mode;
- live YouTubeKit -> isolated smoke;
- device-only -> deferred evidence record during this campaign.

### D. Repair before expansion

If the slice introduces a failure, fix or revert it before adding the next slice. Do not layer new work over an unexplained broken baseline.

### E. Checkpoint and continue

When packet criteria pass, synchronize state/checkpoint and immediately begin the next packet.

## Implementation decision policy

When the docs specify the behavior but not the exact internal technique:

1. use standard Apple/Swift facilities already present;
2. prefer the solution with fewer dependencies/stateful layers;
3. preserve deterministic testability;
4. avoid abstractions with only one speculative future consumer;
5. preserve platform-neutral logic in FocusTubeCore where it genuinely belongs;
6. document only decisions that materially constrain future work.

Minor implementation decisions do not require an ADR.

## External dependency policy

### YouTubeKit

Treat as unstable infrastructure behind `MediaExtracting`. Pin deliberately. Never spread YouTubeKit-specific types into features. A live failure must not break deterministic testability.

### GoogleSignIn / Data API

Routine CI uses fake auth/API responses. Real auth is a narrow integration validation, not a prerequisite for every implementation step.

### Apple build plane

Treat XcodeGen + macOS CI + Simulator as required development infrastructure. CI scripts should discover compatible installed runtimes rather than assume one brittle exact simulator device.

## Progress reporting

Progress is stored, not narrated from memory. The coordinator maintains:

- `.agent/STATE.yaml` — live pointer/current reality;
- `.agent/WAYPOINTS.yaml` — plan/dependencies/status;
- `.agent/checkpoints/` — durable milestone/gate evidence;
- `.agent/HARDENING_BACKLOG.md` — deferred nonblocking quality work.

Do not maintain a second competing progress tracker elsewhere.

## Definition of implementation complete

Implementation complete does not mean perfect or release-certified. It means the V1 architecture/product surface exists, automated gates are green to the extent available without user/device intervention, device-only evidence is honestly deferred, and no known Critical/High issue makes the codebase unsafe to hand to the hardening campaign.

That boundary is deliberate: implementation first, periodic hardening later.