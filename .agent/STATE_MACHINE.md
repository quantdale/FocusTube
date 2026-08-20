# Autonomous Development State Machine

The implementation controller is a continuous state machine. Packet completion transitions directly into the next ready packet.

```text
RECOVERING
   -> READY
   -> WORKING(packet, waypoint)
   -> LOCAL_VALIDATION
   -> REMOTE_APPLE_VALIDATION          [when Apple-specific]
   -> LIVE_INTEGRATION_VALIDATION       [when external/live proof required]
   -> REVIEW_EVIDENCE
       -> FIXING -> LOCAL_VALIDATION
       -> PACKET_COMPLETE
            -> CHECKPOINT               [when gate/milestone crossed]
            -> READY(next packet)
                 -> WORKING(...)

Critical/High regression
   -> BLOCKED_FIX_REQUIRED -> FIXING

Single-path external blocker
   -> PATH_BLOCKED
   -> choose independent READY work if safe

Global blocker, no independent safe work
   -> BLOCKED_HUMAN_INPUT or BLOCKED_UPSTREAM

IC-EXIT passes
   -> IMPLEMENTATION_COMPLETE_READY_FOR_HARDENING
```

## Legal state meanings

- `ready`: durable state is coherent and a next action is known.
- `working`: code/config/docs for the current waypoint are actively changing.
- `validating`: implementation exists but acceptance evidence is incomplete.
- `path_blocked`: one criterion/path is blocked; project continues elsewhere where dependency-safe.
- `blocked_human_input`: no useful safe work remains without a narrow human action.
- `blocked_upstream`: an external dependency is proven to block all remaining useful work in scope.
- `implementation_complete_ready_for_hardening`: M0–M8 implementation campaign passed `IC-EXIT`.

## Transition rules

1. `WORKING -> PACKET_COMPLETE` is illegal without acceptance evidence.
2. Windows-only compile/test evidence cannot satisfy Apple-framework behavior gates.
3. Remote Apple validation is mandatory after changes to project generation, iOS app target, SwiftUI, AVKit/AVFoundation, SwiftData, GoogleSignIn, YouTubeKit integration, entitlements, background modes, or simulator behavior.
4. Live YouTube failures are isolated from deterministic app tests before classifying `BLOCKED_UPSTREAM`.
5. Physical-device-only evidence does not block the active implementation campaign; it is recorded for later hardening/release.
6. Medium/Low debt does not trigger a campaign transition; log it in the hardening backlog.
7. Critical/High regressions always preempt feature progression.
8. A completed packet causes an immediate transition to the next ready packet unless `IC-EXIT` has passed.

## Stale-state recovery

If the recorded state contradicts observed repository evidence:

- do not blindly repeat old work;
- inspect recent commits/tests/checkpoints;
- choose the most recent **proven** good state;
- repair `.agent/STATE.yaml`/`.agent/WAYPOINTS.yaml` to match reality;
- document the reconciliation in evidence.

## Global-stop threshold

A global stop is allowed only when all dependency-safe work is exhausted and one of the true stop conditions in `START_HERE.md` applies.