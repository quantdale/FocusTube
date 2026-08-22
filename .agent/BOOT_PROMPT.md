# Minimal Prompt for an Autonomous Coding Agent

Use this when starting or resuming an agent. Do not paste the entire roadmap into the chat; the repository is the source of truth.

```text
Work autonomously on FocusTube from the repository's current durable state.

First inspect git status/HEAD, then read START_HERE.md, AGENTS.md, .agent/STATE.yaml, .agent/AUTONOMOUS_EXECUTION.md, .agent/WAYPOINTS.yaml, and the active work packet. Resume from the recorded current_waypoint.

Execute the DEVICE_VALIDATION_V1 campaign continuously: keep CI green, diagnose and repair any owner-reported device failures (Batch A A1–A14 follow-ups), record evidence/checkpoints, and advance durable state. Implementation campaigns (IC, HARDENING_V1/V2) are complete with green CI on 2c7646d — do not reopen broad hardening without a recorded Critical/High defect.

Preserve all locked architectural decisions. Fix Critical/High regressions immediately; put nonblocking Medium/Low cleanup in .agent/HARDENING_BACKLOG.md (currently zero open items). Use deterministic tests plus remote macOS/iOS Simulator validation where required. Never claim unobserved evidence; never automate owner credentials or fake device results.

When a path requires unavailable credentials, signing, physical hardware, or a proven broken upstream, record the blocker and continue independent safe work before asking for human input.
```
