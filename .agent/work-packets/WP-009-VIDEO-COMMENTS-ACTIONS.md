# WP-009-VIDEO-COMMENTS-ACTIONS

**Milestone/Gate:** M6 / G6

## Objective

Finish the intentional video consumption screen.

## Required work

- Production video detail layout.
- comments/replies read.
- comments-disabled state.
- post top-level/reply.
- subscribe/unsubscribe.
- like/rate if retained.
- download picker exposes only actual allowed qualities.
- related content remains off by default.

## Acceptance

- G6 passes with authenticated integration evidence for write actions.

## Rules

- Preserve all locked decisions in `START_HERE.md` and `AGENTS.md`.
- Add/update deterministic tests with behavior changes.
- Record exact validation evidence in `.agent/STATE.yaml`.
- Do not advance the packet merely on code inspection.
