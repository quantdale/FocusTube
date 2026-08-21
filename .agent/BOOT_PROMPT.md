# Minimal Prompt for an Autonomous Coding Agent

Use this when starting or resuming an agent. Do not paste the entire roadmap into the chat; the repository is the source of truth.

```text
Work autonomously on FocusTube from the repository's current durable state.

First inspect git status/HEAD, then read START_HERE.md, AGENTS.md, .agent/STATE.yaml, .agent/AUTONOMOUS_EXECUTION.md, .agent/WAYPOINTS.yaml, and the active work packet. Resume from the recorded current_waypoint.

Execute the INTEGRATION_COMPLETION_V1 campaign continuously (integration, validation, HARDENING_V1, personal release). Do not stop after one task or work packet: implement, validate, fix failures, record evidence/checkpoints, advance durable state, and continue to the next dependency-safe packet until IC-EXIT passes or a true global stop condition is recorded.

Preserve all locked architectural decisions. Fix Critical/High regressions immediately; put nonblocking Medium/Low cleanup in .agent/HARDENING_BACKLOG.md. Do not begin the broad hardening campaign. Use deterministic tests plus remote macOS/iOS Simulator validation where required. Never claim unobserved evidence.

When a path requires unavailable credentials, signing, physical hardware, or a proven broken upstream, record the blocker and continue independent safe work before asking for human input.
```
