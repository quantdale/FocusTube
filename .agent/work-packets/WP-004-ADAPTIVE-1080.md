# WP-004-ADAPTIVE-1080

**Milestone/Gate:** M1 / G1

## Objective

Prove 1080p adaptive download and native mux.

## Required work

- Select exactly 1080 video-only stream when combined 1080 is absent.
- Select compatible audio-only stream.
- Download components.
- Mux with native AVFoundation, preferring passthrough.
- Validate final audio+video asset.
- Measure temp-space requirement.
- Add deterministic mux fixture and live representative proof.

## Acceptance

- Representative 1080p adaptive video becomes one valid offline file.
- No FFmpeg added.
- If impossible with supported source formats, stop and open ADR instead of adding workaround silently.

## Rules

- Preserve all locked decisions in `START_HERE.md` and `AGENTS.md`.
- Add/update deterministic tests with behavior changes.
- Record exact validation evidence in `.agent/STATE.yaml`.
- Do not advance the packet merely on code inspection.
