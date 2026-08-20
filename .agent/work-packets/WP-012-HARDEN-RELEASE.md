# WP-012-HARDEN-RELEASE

**Milestone/Gate:** M9-M10 / G9-G10

## Objective

Harden and ship the personal-use build.

## Required work

- network/storage/process-termination torture tests.
- extractor failure campaign.
- migration/reconciliation campaign.
- accessibility audit.
- security/log redaction audit.
- fresh-agent recovery proof.
- real iPhone installation/signing.
- physical download/offline/PiP/background verification.
- document known limitations.

## Acceptance

- Critical/High defects zero.
- G9 and G10 pass.
- usable personal release checkpoint recorded.

## Rules

- Preserve all locked decisions in `START_HERE.md` and `AGENTS.md`.
- Add/update deterministic tests with behavior changes.
- Record exact validation evidence in `.agent/STATE.yaml`.
- Do not advance the packet merely on code inspection.
