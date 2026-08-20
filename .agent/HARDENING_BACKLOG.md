# Hardening Backlog — Deferred During Implementation Campaign

This file is the parking lot for nonblocking Medium/Low quality work discovered while implementing M0–M8. It exists to prevent autonomous agents from spending the implementation campaign polishing indefinitely.

## Rules

- Critical/High correctness, data-integrity, security, secret-leak, build, or no-Shorts regressions are **not** deferred; fix them immediately.
- Medium/Low debt that does not block the active acceptance gate is logged here and implementation continues.
- Do not start a broad hardening sweep during `IMPLEMENTATION_V1` unless the user/state explicitly changes campaign.
- Each item should be specific enough for a later hardening agent to reproduce or inspect.

## Item template

```markdown
### HB-xxx — short title
- Severity: Medium | Low
- Discovered in: WP-xxx / commit
- Area: subsystem/files
- Evidence/reproduction: ...
- Impact: ...
- Suggested hardening action: ...
- Blocks implementation: no
```

## Backlog

_No implementation-deferred technical items recorded yet._

Administrative note: repository visibility was observed as public during bootstrap. This is not an implementation blocker and should be handled outside code when desired.