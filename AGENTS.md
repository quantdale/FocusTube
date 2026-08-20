# AGENTS.md — FocusTube Autonomous Engineering Contract

This contract applies to every AI coding agent, subagent, and fresh session operating in this repository.

## Prime directive

**Continue the implementation campaign autonomously until the repository reaches `implementation_complete_ready_for_hardening`, unless a true stop condition is recorded.** A completed work packet is a transition point, not a reason to stop.

The repository is intentionally designed so the user does not need to supervise normal implementation decisions.

## Source-of-truth hierarchy

When instructions disagree, use this order:

1. explicit locked user decision recorded in an accepted ADR or `docs/00-PRODUCT-SPEC.md`;
2. `AGENTS.md`;
3. `.agent/STATE.yaml` for current reality and waypoint;
4. `.agent/AUTONOMOUS_EXECUTION.md` and `.agent/OPERATING_CONTRACT.md`;
5. subsystem specifications in `docs/`;
6. current work packet;
7. existing implementation.

Existing code does not overrule a locked specification merely because it already exists.

## Session-start obligations

Every fresh session must:

1. inspect git status/HEAD without modifying anything;
2. read `.agent/STATE.yaml`;
3. read `.agent/WAYPOINTS.yaml`;
4. read the active work packet;
5. inspect relevant code/tests;
6. run the cheapest available baseline before broad edits;
7. resume from the recorded waypoint.

If state and code disagree, investigate and correct the state only after evidence. Never guess progress from filenames alone.

## Continuous autonomy rules

- Do not ask for permission to execute work already authorized by the roadmap.
- Do not wait after a packet passes. Update state and continue.
- Do not ask the user to choose between equivalent internal implementation details. Use the simplest compliant option.
- Do not perform broad cleanup just because you noticed it. Log nonblocking Medium/Low debt in `.agent/HARDENING_BACKLOG.md`.
- Fix Critical/High regressions immediately before feature progress continues.
- If one path is blocked by credentials, signing, physical hardware, or an upstream service, continue independent deterministic work where possible.
- Do not mark a gate complete because implementation looks plausible. Observe evidence.

## Architectural invariants

- `FocusTubeCore` remains free of UIKit, SwiftUI, AVKit, AVFoundation, SwiftData, GoogleSignIn, and YouTubeKit imports.
- YouTubeKit stays behind the `MediaExtracting` boundary; feature UI never calls it directly.
- YouTube Data API access stays behind typed client/protocol boundaries.
- Download mutable state is an explicit state machine, not unrelated booleans.
- Network, extractor, auth, clock, filesystem, download transport, and relevant persistence behavior retain deterministic test seams.
- Shared mutable service state uses actors; UI-facing state is `@MainActor`.
- Download resolution policy is exactly 1080/720/480/360, never higher.
- No yt-dlp, remote extractor, backend, or FFmpeg convenience fallback may appear without an accepted ADR.
- Shorts UI/routes/vertical swipe behavior/implicit autoplay-next are prohibited.
- Real secrets, OAuth refresh tokens, cookies, passwords, 2FA data, private account responses, and API keys are never committed or placed in fixtures.
- Real Google login credentials are never automated through UI tests.

## Implementation quality bar

Critical/High regressions block progress. A checkpoint cannot be accepted with:

- failing deterministic tests caused by project changes;
- iOS target build failure;
- simulator launch crash;
- known final-media corruption/orphaning path;
- a code path that can render blocked short-form content in Home/Search;
- secret leakage;
- unsafe persistence migration/data-loss behavior;
- tests weakened merely to obtain green status.

Medium/Low issues may be deferred only when logged with impact and reproduction/evidence when available.

## Work-packet discipline

Use `.agent/WAYPOINTS.yaml` as the machine-readable plan and `.agent/work-packets/INDEX.md` for narrative ordering.

For each packet:

1. prove prerequisites;
2. decompose into the smallest coherent implementation slices;
3. implement one slice;
4. validate at the cheapest appropriate layer;
5. repeat until packet acceptance passes;
6. run its gate suite;
7. write checkpoint/evidence;
8. mark packet complete and advance.

Do not begin a dependent packet while its dependency gate is genuinely broken. Preparatory deterministic work may proceed only if it cannot mask the blocked dependency or create speculative architecture.

## Parallel/subagent rules

A single coordinator owns `.agent/STATE.yaml`, `.agent/WAYPOINTS.yaml`, checkpoint creation, and final integration decisions.

Subagents may be used for disjoint investigations or implementation slices when write scopes do not overlap. Each subagent must receive:

- active packet and exact objective;
- allowed files/area;
- relevant invariants;
- required tests/evidence;
- prohibition on updating global state directly.

The coordinator integrates, validates, and updates durable state. Never allow multiple workers to race-write global state.

## Validation matrix

- Platform-neutral logic: `swift test` locally when Swift is available.
- iOS compile/project generation: macOS/Xcode CI.
- SwiftUI/UI behavior: XCUITest/iOS Simulator.
- YouTubeKit behavior: isolated live smoke tests plus deterministic fake-extractor tests.
- Background/PiP/lock-screen semantics: automate what Simulator supports; record physical-device-only checks for later release/hardening.
- Google auth: deterministic fake auth in routine CI; real OAuth is an integration gate, never a password-driven automation flow.

## Commit/checkpoint discipline

Prefer small coherent commits aligned to the active packet. Never force-push shared/default branches. Do not mix unrelated refactors with feature work.

At a meaningful checkpoint:

- deterministic tests must be green or the known failure explicitly classified;
- `.agent/STATE.yaml` must describe reality;
- packet/waypoint status must be current;
- gate evidence must be recorded;
- next action must be executable by a fresh agent.

Generated `FocusTube.xcodeproj/`, DerivedData, simulator artifacts, xcresult bundles, downloaded media, local secrets, and generated credentials are not committed.

## Evidence standard

Examples:

```yaml
evidence:
  - id: ev-20260820-wp000-core
    kind: test
    command: swift test
    result: pass
  - id: ev-20260820-wp000-ios
    kind: ci
    workflow: ios-ci
    run: 123456789
    result: pass
  - id: ev-20260820-wp002-playback
    kind: simulator
    artifact: playback-started.png
    result: pass
```

Never invent run IDs, screenshots, device results, or test outcomes.

## Stop/escalation policy

Do not escalate ordinary engineering uncertainty. Investigate it.

Escalate only when:

- safe credentials/account action is indispensable;
- a locked decision must change;
- required external infrastructure cannot be created by available tooling;
- upstream breakage is proven and blocks all useful dependent work;
- continuing risks destructive or security-sensitive behavior.

Before escalating, update `.agent/STATE.yaml` with `blocked_reason`, attempted mitigations, evidence, and the smallest human action required.

## Campaign boundary

The active campaign is implementation M0–M8. Broad hardening/torture/a11y/performance cleanup is deferred to a later campaign, except Critical/High correctness or security issues that block safe implementation.

When `IC-EXIT` passes, set status to `implementation_complete_ready_for_hardening` and stop broad feature construction.