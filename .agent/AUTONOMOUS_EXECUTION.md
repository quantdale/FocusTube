# Autonomous Execution Protocol

This is the operational algorithm for running FocusTube without ongoing human supervision.

## Objective

Drive the active implementation campaign from the current durable waypoint through `IC-EXIT` while preserving correctness, reproducibility, and recoverability.

## Core rule

**A successful iteration automatically starts the next iteration.** The agent does not stop merely because a test passed, a commit was made, or a work packet completed.

## Phase 0 — Recover

1. Inspect repository HEAD/status and recent commits.
2. Read `AGENTS.md`, `.agent/STATE.yaml`, `.agent/WAYPOINTS.yaml`, and the active packet.
3. Reconcile any uncommitted work with state/checkpoint records.
4. Identify the active milestone, gate, packet, waypoint, and smallest next action.
5. Verify the relevant baseline cheaply before broad edits.

If `.agent/STATE.yaml` is stale but code/evidence clearly advanced, repair state from observed evidence. Do not downgrade or advance based on assumptions.

## Phase 1 — Select work deterministically

Selection order:

1. fix any active Critical/High regression;
2. continue the `current_work_packet` if its prerequisites are satisfied;
3. if current packet is complete but state was not advanced, perform checkpoint + state transition;
4. otherwise select the first `ready` waypoint in `.agent/WAYPOINTS.yaml` whose dependencies are all complete;
5. never select later work solely because it is easier or more interesting.

If a packet has multiple acceptance criteria, prefer the criterion that retires the highest technical risk or unlocks the most dependent work.

## Phase 2 — Plan the smallest coherent slice

Before editing, determine:

- exact behavior to change;
- files/interfaces likely involved;
- deterministic tests to add/change;
- whether Apple-only validation is required;
- expected evidence;
- rollback boundary.

Do not turn this into a new product-design exercise. Follow the packet/spec.

## Phase 3 — Implement

Implementation rules:

- preserve architecture boundaries;
- avoid speculative abstractions not required by this or an imminent dependent packet;
- add test seams before external dependency logic becomes deeply coupled;
- keep feature state explicit and typed;
- keep error conditions observable and actionable;
- prefer native platform facilities already selected by architecture;
- do not gold-plate UI during media/core viability work.

## Phase 4 — Validate locally

Run the cheapest relevant checks first. Typical order:

1. focused unit test(s);
2. package test suite (`swift test`) for core changes;
3. static/config sanity checks;
4. broader deterministic tests affected by the change.

A failure introduced by the current slice is fixed before moving on. A pre-existing unrelated failure must be classified and recorded, not silently ignored.

## Phase 5 — Validate on Apple build plane

Required when touching project generation, iOS target code, SwiftUI, AVKit/AVFoundation, SwiftData, GoogleSignIn, YouTubeKit integration, entitlements, background modes, or simulator behavior.

Expected sequence:

```text
XcodeGen -> resolve packages -> build/test -> boot simulator -> install/launch -> XCUITest/smoke -> collect xcresult/log/screenshots
```

Do not repeatedly retry a failing CI job without reading the failing step/log first. One retry is acceptable for an identified infrastructure/transient failure; repeated identical failure means investigate.

## Phase 6 — External/live dependency validation

YouTubeKit live extraction and real YouTube API behavior are separated from deterministic tests.

- deterministic fake-extractor/API tests remain mandatory;
- live smoke failure does not justify weakening deterministic coverage;
- classify live failures as app regression, fixture/content issue, regional/network issue, or upstream extraction/API change;
- do not introduce unauthorized fallbacks as a panic response.

## Phase 7 — Record evidence

Evidence must answer: **what exact acceptance criterion was proven, where, and by what observed result?**

Update `.agent/STATE.yaml` and, for gate/milestone transitions, create a checkpoint per `.agent/CHECKPOINT_PROTOCOL.md`.

## Phase 8 — Advance

When packet acceptance passes:

1. mark packet `complete` in `.agent/WAYPOINTS.yaml`;
2. update milestone/gate state;
3. set the next packet/waypoint;
4. record `last_good_commit` or equivalent observed commit SHA when available;
5. immediately begin the next ready packet.

Do not wait for human acknowledgement.

## Blocker decision tree

### Code/test failure
Fix it. Do not classify as external until evidence rules out project code/configuration.

### CI infrastructure failure
Inspect versions/runtime availability/logs. Adapt scripts within documented supported ranges. Retry only after a reasoned change or clear transient classification.

### YouTubeKit/upstream extraction failure
Confirm with a known public long-form sample and isolate against deterministic adapter tests. If upstream is proven broken, record `BLOCKED_UPSTREAM`, preserve local-only policy, and continue unrelated deterministic/API/UI work that does not rely on live extraction if doing so is not speculative.

### Google credentials/OAuth configuration unavailable
Finish fake-auth plumbing, typed API client, deterministic screens/tests, and configuration documentation. Mark real OAuth evidence pending. Continue independent implementation. Never request or store the user's password/2FA/cookies.

### Physical iPhone unavailable
Do not block implementation. Record device-only checks as deferred to hardening/release; validate build/simulator/testable behavior now.

### Locked architecture appears impossible
Create an ADR proposal containing evidence, attempted compliant options, impact, and smallest decision required. Do not silently adopt an alternative. Continue independent work if possible.

### Ambiguous minor UX/implementation choice
Choose the simplest behavior consistent with product/UX specs and test it. Do not ask the user.

## No-idle rule

When blocked on one criterion, search for an independent ready criterion in the same packet or next dependency-safe packet. The agent should only become globally blocked when **no useful roadmap work can proceed safely**.

## Context-window handoff

Before ending a long session or when context is becoming unreliable:

1. finish or roll back the current atomic edit;
2. run the cheapest relevant validation;
3. update state with exact partial status;
4. include files changed, tests run, known failures, and next command/action;
5. commit a coherent checkpoint when appropriate.

A new agent must never need hidden chain-of-thought or chat history to continue.

## Campaign completion

Stop the continuous implementation loop only when:

- `IC-EXIT` passes and state is `implementation_complete_ready_for_hardening`; or
- a global true stop condition exists and has been fully recorded.

Do not automatically enter the hardening campaign.