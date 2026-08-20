# Durable Checkpoint Protocol

Checkpoints make long autonomous runs recoverable across agent/session/context loss.

## When a checkpoint is required

Create a checkpoint when:

- a milestone gate passes;
- a work packet materially changes an external/system boundary;
- a long session is ending with meaningful verified progress;
- a blocker is severe enough that another agent may need to resume later;
- implementation campaign reaches `IC-EXIT`.

Small internal commits do not each require a checkpoint file.

## Checkpoint path

Use:

```text
.agent/checkpoints/YYYYMMDD-HHMM-<packet>-<short-name>.md
```

Use local project time when known. Avoid overwriting prior checkpoints.

## Required checkpoint contents

```markdown
# Checkpoint — <packet> <summary>

- Campaign: IMPLEMENTATION_V1
- Milestone/Gate: Mx / Gx
- Packet: WP-xxx
- State: complete | partial | blocked
- Commit: <observed SHA or unknown>

## What changed
- ...

## Acceptance evidence
- command/workflow/device/artifact + observed result

## Known failures or deferred items
- ...

## Durable decisions made
- none, or ADR reference

## Exact next waypoint
- one executable next action

## Resume commands
```text
<commands that materially help the next agent>
```
```

## Evidence requirements

Evidence must be reproducible or attributable:

- command plus result;
- CI workflow/run/job plus result;
- simulator/device identity plus action/result;
- artifact name/path;
- test case/suite plus pass/fail count;
- relevant error/log excerpt location for blockers.

Do not write "tested" without saying how.

## State synchronization

A checkpoint and `.agent/STATE.yaml` must agree on:

- current campaign;
- completed milestone/gate;
- active/next packet;
- blockers;
- next executable waypoint.

If they disagree, `.agent/STATE.yaml` is the live pointer but the discrepancy must be repaired before new feature work.

## Partial checkpoint rule

When stopping mid-packet, never mark the packet complete. Record:

- acceptance criteria already proven;
- criteria still missing;
- exact files/subsystems touched;
- last validation command/result;
- next action.

## Commit hygiene

Checkpoint commits should be coherent and recoverable. Never force-push to erase history in order to make the state look cleaner.