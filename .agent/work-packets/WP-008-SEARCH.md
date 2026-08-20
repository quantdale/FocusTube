# WP-008-SEARCH

**Milestone/Gate:** M5 / G5

## Objective

Add quota-aware deliberate search.

## Required work

- Explicit submit only.
- Local recent-query suggestions.
- YouTube search API adapter.
- hydrate durations then filter.
- quota-aware pagination.
- quota-exhausted UX.
- deterministic API fixtures.

## Acceptance

- No remote call per keystroke.
- blocked short results never render.
- G5 passes.

## Rules

- Preserve all locked decisions in `START_HERE.md` and `AGENTS.md`.
- Add/update deterministic tests with behavior changes.
- Record exact validation evidence in `.agent/STATE.yaml`.
- Do not advance the packet merely on code inspection.
