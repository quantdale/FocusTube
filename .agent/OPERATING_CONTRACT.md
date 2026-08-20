# Agent Operating Contract

## Operating mode

FocusTube currently runs in **continuous autonomous implementation mode**. Human supervision is optional for ordinary engineering work. The agent is expected to advance through packets without waiting between them.

## Session start

1. Inspect `git status --short --branch` and current HEAD.
2. Read `AGENTS.md`.
3. Read `.agent/STATE.yaml` and `.agent/WAYPOINTS.yaml`.
4. Read the active work packet and referenced subsystem docs.
5. Inspect relevant code/tests before editing.
6. Run the cheapest baseline appropriate to the environment.
7. Continue from `current_waypoint`.

## During work

- Maintain a green deterministic baseline.
- Add or update tests with behavioral changes.
- Do not bypass a gate by weakening assertions unless the governing specification itself is changed through an accepted ADR.
- Prefer interfaces/adapters at unstable external boundaries.
- Preserve YouTubeKit local-only extraction and exact 1080/720/480/360 quality policy.
- Preserve Windows-testable FocusTubeCore boundaries.
- Use state machines/actors for long-lived mutable subsystems such as downloads.
- Treat external URLs/tokens as ephemeral; persistence stores stable identifiers/state, not assumptions that signed stream URLs remain valid forever.
- Fix Critical/High implementation defects immediately.
- Send nonblocking Medium/Low cleanup to `.agent/HARDENING_BACKLOG.md`.
- Avoid aesthetic polish until the packet's functional acceptance is secure.

## Work packet completion

A packet completes only when all required acceptance criteria have observed evidence or are explicitly designated as later physical-device-only evidence by the acceptance-gate document.

On completion:

1. update `.agent/WAYPOINTS.yaml` status;
2. update `.agent/STATE.yaml` current/next waypoint and evidence;
3. create a checkpoint when crossing a gate/milestone;
4. continue immediately to the next dependency-safe packet.

## State ownership

Only one coordinator edits global durable state. Subagents may propose changes or work in disjoint scopes but must not race-write `.agent/STATE.yaml`, `.agent/WAYPOINTS.yaml`, or checkpoint files.

## End-of-slice requirements

Before leaving an implementation slice:

- record exact validation performed;
- do not leave unexplained failing tests caused by the slice;
- keep the repository buildable at checkpoint boundaries;
- update the next action if the previous waypoint changed;
- preserve enough detail that a fresh session can resume without chat history.

## Fresh-session recovery invariant

At any checkpoint, a new agent reading only the repository must be able to answer:

- What campaign are we in?
- What is complete?
- What is currently being implemented?
- What evidence is missing?
- What exact action should happen next?
- What is blocked/deferred and why?

If those answers are not recoverable from `.agent/`, the current session is not allowed to declare a checkpoint complete.