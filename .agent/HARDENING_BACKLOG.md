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

### HB-001 — VideoPageView registers onProgress after loadAndPlay
- Severity: Low
- Discovered in: INTEGRATION_COMPLETION_V1 audit (cba7e67 era)
- Area: App/Video/VideoPageView.swift
- Evidence/reproduction: `coordinator.onProgress = ...` is assigned after `await coordinator.loadAndPlay(...)` returns; progress callbacks fired during early playback setup are missed.
- Impact: first moments of playback progress may not render.
- Suggested hardening action: register the callback before calling loadAndPlay.
- Blocks implementation: no

### HB-002 — reattached downloads restart progress aggregation at zero
- Severity: Low
- Discovered in: reattachment slice (0a0683f)
- Area: App/Download/BackgroundDownloadTransport.swift, App/Download/DownloadManager.swift
- Evidence/reproduction: after relaunch reattachment, byte counts are not seeded from the persisted record; UI progress restarts from 0 until the next cumulative didWriteData event.
- Impact: cosmetic progress regression after relaunch; correctness unaffected (URLSession totals are cumulative).
- Suggested hardening action: seed componentProgress from the persisted record on attach.
- Blocks implementation: no

### HB-003 — tiny event window between reattach registration and coordinator attach
- Severity: Low
- Discovered in: reattachment slice (0a0683f)
- Area: App/Download/DownloadManager.swift reconcileOnLaunch
- Evidence/reproduction: a .completed delegate event landing between transport handler registration and coordinator.attach is dropped; that transfer would sit .downloading until next retry.
- Impact: rare stuck record after a precisely-timed relaunch.
- Suggested hardening action: buffer early events in the transport or re-check task states after attach.
- Blocks implementation: no

Administrative note: repository visibility was observed as public during bootstrap. This is not an implementation blocker and should be handled outside code when desired.