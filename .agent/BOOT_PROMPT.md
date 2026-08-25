# Minimal Prompt for an Autonomous Coding Agent

Use this when starting or resuming an agent. Do not paste the entire roadmap into chat; the repository is the source of truth.

```text
Work autonomously on FocusTube from the repository's current durable state.

First verify that you are inside the FocusTube repository/worktree (repo root, remote, branch, HEAD) and that no worker from another repository is sharing or mutating this state. Then inspect git status/HEAD and read START_HERE.md if present, AGENTS.md, .agent/PLANNER_HANDOFF.md, .agent/EXECUTION_PROMPT.md, .agent/STATE.yaml, .agent/AUTONOMOUS_EXECUTION.md, .agent/WAYPOINTS.yaml, .agent/HARDENING_BACKLOG.md, and the active work packet.

If .agent/EXECUTION_PROMPT.md is Status: ACTIVE, reconcile it against current main and resume the first genuinely incomplete requirement. The current ACTIVE campaign is HARDENING_V3_SYSTEMIC_DEBT_CLOSURE; its packet is .agent/work-packets/H3-CAMPAIGN.md. DDV2 is terminal and its automated baseline is green. DEVICE_VALIDATION remains downstream owner-only evidence and must not prevent safe deterministic H3 engineering.

At H3 start, reconcile any stale STATE/WAYPOINTS labels before broad code edits. Do not redo landed work merely because an old state label is stale.

Continue through H3 workstreams autonomously. For every fix, inspect affected callers/consumers and codebase-wide consequences rather than limiting review to the changed file. Fix Critical/High regressions immediately; close the recorded HB-015..HB-030 debt according to the active campaign; record only genuinely residual nonblocking debt with evidence. Keep deterministic tests and remote macOS/iOS Simulator validation truthful and fail-closed.

A single coordinator owns .agent/STATE.yaml, .agent/WAYPOINTS.yaml, campaign/checkpoint files, and integration decisions. Subagents may work only in disjoint scopes and may not race-write global state. Never mix another repository's prompt/state/worktree into FocusTube.

Never claim unobserved device/account/live-service evidence and never automate owner credentials. When a path needs unavailable physical hardware, credentials, signing, or a proven broken upstream, record the blocker and continue independent safe work.

Do not stop after one packet or one green test. Stop only when H3-EXIT is satisfied and no safe ready agent-actionable work remains, or a true AGENTS.md stop condition blocks all useful progress. Commit/push durable checkpoints and final state so the next /goal continue session can resume from GitHub.
```
