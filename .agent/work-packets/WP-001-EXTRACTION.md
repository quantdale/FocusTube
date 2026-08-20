# WP-001-EXTRACTION

**Milestone/Gate:** M1 / G1

## Objective

Implement the local-only YouTubeKit extraction boundary.

## Required work

- Define FocusTube-owned normalized media/stream models.
- Define `MediaExtracting`.
- Implement `YouTubeKitMediaExtractor` with local method only.
- Filter normalized video qualities to exact allowed set.
- Preserve native-playability/container/track metadata.
- Add fake extractor and deterministic selection tests.
- Add opt-in live smoke against a known long-form video.

## Acceptance

- No feature layer imports YouTubeKit directly.
- No 1440p/2160p escapes normalization.
- Live local extraction produces at least one usable allowed stream or a typed upstream failure.

## Rules

- Preserve all locked decisions in `START_HERE.md` and `AGENTS.md`.
- Add/update deterministic tests with behavior changes.
- Record exact validation evidence in `.agent/STATE.yaml`.
- Do not advance the packet merely on code inspection.
