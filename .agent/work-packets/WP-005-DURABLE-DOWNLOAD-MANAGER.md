# WP-005-DURABLE-DOWNLOAD-MANAGER

**Milestone/Gate:** M2 / G2

## Objective

Turn the proof into a resilient engine.

## Required work

- Actor-based DownloadManager.
- Explicit state enum/transitions.
- SwiftData DownloadRecord.
- Background task reconciliation after relaunch.
- retry/cancel/pause policy.
- expired URL re-resolution.
- storage preflight and cleanup.
- Active/Completed Downloads screens with fixture transport.

## Acceptance

- G2 passes including relaunch/retry/storage/cancel tests.

## Rules

- Preserve all locked decisions in `START_HERE.md` and `AGENTS.md`.
- Add/update deterministic tests with behavior changes.
- Record exact validation evidence in `.agent/STATE.yaml`.
- Do not advance the packet merely on code inspection.
