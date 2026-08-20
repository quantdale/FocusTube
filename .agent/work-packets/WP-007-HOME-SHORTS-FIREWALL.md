# WP-007-HOME-SHORTS-FIREWALL

**Milestone/Gate:** M4 / G4

## Objective

Build useful chronological Home with structural Shorts exclusion.

## Required work

- Aggregate subscription uploads.
- Hydrate duration/metadata.
- Centralize ShortFormPolicy.
- Apply before rendering.
- Block `/shorts/` deep links.
- Explicit Load More.
- cache/staleness/pull-to-refresh.
- XCUITest proves no blocked cards.

## Acceptance

- G4 passes; 180s boundary and Shorts path regressions covered.

## Rules

- Preserve all locked decisions in `START_HERE.md` and `AGENTS.md`.
- Add/update deterministic tests with behavior changes.
- Record exact validation evidence in `.agent/STATE.yaml`.
- Do not advance the packet merely on code inspection.
