# Agent Operating Contract

## Session start

1. Read `AGENTS.md`.
2. Read `.agent/STATE.yaml`.
3. Read the active work packet.
4. Inspect relevant code/tests before editing.
5. State the concrete gate being advanced in commit/work notes.

## During work

- Maintain a green deterministic baseline.
- Add tests with behavior changes.
- Do not bypass a failing gate by weakening assertions unless the specification itself was wrong and changed through ADR.
- Prefer interfaces/adapters at unstable external boundaries.
- Preserve local-only extraction.
- Preserve the exact quality ladder.
- Preserve Windows-testable FocusTubeCore boundaries.

## End of iteration

Update `.agent/STATE.yaml` with:

- active milestone/work packet;
- what changed;
- exact validation performed;
- current blockers;
- next smallest waypoint.

If a milestone gate passes, add a checkpoint Markdown file under `.agent/checkpoints/` with command/workflow/device evidence.

## Fresh-session recovery test

At least once per major milestone, assume no chat context exists. A fresh agent should be able to read the repository and identify the next work without asking the user to reconstruct project history.
