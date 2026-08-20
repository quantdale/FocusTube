# WP-002-PLAYBACK

**Milestone/Gate:** M1 / G1

## Objective

Prove native online playback.

## Required work

- Build `PlaybackCoordinator` owning AVPlayer lifecycle.
- Wrap AVPlayerViewController for SwiftUI.
- Select highest allowed natively playable combined stream first.
- Implement loading/error states.
- Persist/test basic resume position seam without final library polish.
- Simulator live smoke where network permits.

## Acceptance

- A real long-form selection reaches AVPlayer without WebView.
- View recreation does not reset the player unexpectedly.
- >1080p is never selected.

## Rules

- Preserve all locked decisions in `START_HERE.md` and `AGENTS.md`.
- Add/update deterministic tests with behavior changes.
- Record exact validation evidence in `.agent/STATE.yaml`.
- Do not advance the packet merely on code inspection.
