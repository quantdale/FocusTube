# Minimal Prompt for an Autonomous Coding Agent

Use this when starting or resuming an agent. Do not paste the entire roadmap into chat; the repository is the source of truth.

```text
Work autonomously on FocusTube from the repository's current durable state.

First verify that you are inside the FocusTube repository/worktree (repo root, remote, branch, HEAD, origin/main) and that no worker from another repository is sharing or mutating this state. Then inspect git status and read START_HERE.md, AGENTS.md, .agent/PLANNER_HANDOFF.md, .agent/EXECUTION_PROMPT.md, .agent/STATE.yaml, .agent/AUTONOMOUS_EXECUTION.md, .agent/WAYPOINTS.yaml, .agent/HARDENING_BACKLOG.md, and any genuinely active packet.

If .agent/EXECUTION_PROMPT.md is Status: ACTIVE, reconcile it against current main and resume the first genuinely incomplete requirement without redoing landed work.

If the execution prompt is COMPLETE, obey .agent/STATE.yaml. Current durable truth (2026-08-26): HARDENING_V3_SYSTEMIC_DEBT_CLOSURE passed H3-EXIT; qualified code SHA 7a70943; the hardening backlog is closed; the whole-repository re-audit found no residual Critical/High agent-actionable defects; no open GitHub issues/PRs exist at planner audit; current Core Tests and iOS CI are green. There is NO active agent-side coding campaign.

The remaining waypoint is DEVICE_VALIDATION_V1_REFRESHED: owner-executed physical-iPhone Batch A A1-A14 plus one authenticated opt-in live-smoke dispatch against 7a70943. Never claim, synthesize, or automate owner credentials/device evidence.

Do not manufacture another implementation or hardening campaign merely to keep working. If no new evidence-backed defect exists, stop with the repository clean and report that owner validation is the next action. If a fresh CI regression or owner-reported defect is evidenced and is agent-actionable, root-cause and repair it under the repository invariants, validate truthfully, update durable state, and commit/push the correction.

A single coordinator owns .agent/STATE.yaml, .agent/WAYPOINTS.yaml, campaign/checkpoint files, and integration decisions. Subagents may work only in disjoint scopes and may not race-write global state. Never mix another repository's prompt/state/worktree into FocusTube.
```