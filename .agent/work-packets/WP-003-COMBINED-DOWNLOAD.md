# WP-003-COMBINED-DOWNLOAD

**Milestone/Gate:** M1 / G1

## Objective

Prove simplest complete offline path.

## Required work

- Build initial download request model and quality picker domain.
- Use background URLSession for a combined stream.
- Move completed file atomically into Application Support.
- Validate tracks/duration.
- Index minimal record.
- Play final local file through AVPlayer.
- Add fixture download tests and one live proof.

## Acceptance

- Combined download completes at an allowed quality.
- Offline AVPlayer playback succeeds.
- Partial/temp files never masquerade as completed.

## Rules

- Preserve all locked decisions in `START_HERE.md` and `AGENTS.md`.
- Add/update deterministic tests with behavior changes.
- Record exact validation evidence in `.agent/STATE.yaml`.
- Do not advance the packet merely on code inspection.
