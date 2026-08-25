# START HERE — FocusTube Autonomous Engineering Entry Point

FocusTube is designed to be recoverable by a fresh AI coding agent with **zero chat history and minimal human supervision**. Repository state, not conversation memory, is authoritative.

## Current mission

The implementation and hardening campaigns are complete. The repository is now in external validation handoff, not another autonomous construction wave.

- Last coding campaign: `HARDENING_V3_SYSTEMIC_DEBT_CLOSURE` — **COMPLETE**.
- Exit gate: `H3-EXIT` — passed 2026-08-26.
- Qualified code baseline: `7a70943`.
- Automated evidence at that code SHA: Core Tests run `32891558919` SUCCESS; iOS CI run `32891558884` SUCCESS, including Build Debug/Release, 141 XCTest, journeys 20/20, and the fail-closed Gate.
- Latest docs-tip evidence at `f1dcca`: Core Tests run `32898272247` SUCCESS; iOS CI run `32898272210` SUCCESS.
- Hardening backlog: HB-015..HB-030 resolved with evidence; H3-07 whole-repository re-audit found no residual Critical/High agent-actionable defect and only two bounded Low notes.
- Open GitHub issues/PRs at the 2026-08-26 planner audit: none.
- Current downstream waypoint: `DEVICE_VALIDATION_V1_REFRESHED` — owner-executed physical-iPhone Batch A A1–A14 plus one authenticated opt-in live-smoke dispatch against `7a70943`.

**Planner verdict:** there is no legitimate next agent-side implementation/hardening campaign. Do not manufacture churn. A new coding campaign requires new evidence-backed defects or an explicit new product directive.

## Mandatory reading order

Before making changes in a fresh session, read in this order:

1. `START_HERE.md`
2. `AGENTS.md`
3. `.agent/PLANNER_HANDOFF.md`
4. `.agent/EXECUTION_PROMPT.md`
5. `.agent/STATE.yaml`
6. `.agent/AUTONOMOUS_EXECUTION.md`
7. `.agent/WAYPOINTS.yaml`
8. `.agent/OPERATING_CONTRACT.md`
9. `.agent/HARDENING_BACKLOG.md`
10. an active work packet only if durable state proves one exists
11. subsystem docs/tests relevant to any newly evidenced defect

Only read the entire documentation set when a decision actually spans multiple subsystems. Prefer targeted context over repeatedly rereading every file.

## Recovery algorithm

A fresh agent must be able to resume with this algorithm:

1. Verify repository root/remote and run `git status --short --branch`; inspect local HEAD and `origin/main`.
2. Read `.agent/EXECUTION_PROMPT.md`, `.agent/STATE.yaml`, and `.agent/WAYPOINTS.yaml`.
3. If the execution prompt is `Status: ACTIVE`, reconcile it against current main and resume its first genuinely incomplete requirement.
4. If the execution prompt is complete and state says only `DEVICE_VALIDATION_V1_REFRESHED` remains, do not start code work merely because the repository is idle.
5. Check whether new evidence exists: a red hosted workflow, owner-reported device failure, new issue/PR, or explicit new product directive.
6. If a new defect is real and agent-actionable, inspect the implementation/tests, run the cheapest useful baseline, repair it under the locked invariants, validate truthfully, update durable state, and commit/push.
7. If no such evidence exists, stop cleanly and report that owner device/account validation is the next action.

Do not ask the user to restate project history that exists in the repository.

## Locked architecture

These are not open design questions:

- Native iOS, iPhone-first, minimum iOS 17.0.
- SwiftUI + Swift 6 language mode.
- AVPlayer + AVPlayerViewController for playback.
- YouTubeKit is the only extractor; `.local` extraction only.
- No yt-dlp fallback and no remote extraction service.
- Download qualities are exactly **1080p, 720p, 480p, 360p**; 1080p is the absolute ceiling.
- Never transcode merely to manufacture a missing quality.
- URLSession background sessions for downloads.
- AVFoundation native composition/export for adaptive muxing before any reconsideration of FFmpeg.
- SwiftData for metadata; filesystem for downloaded media.
- GoogleSignIn for OAuth; typed direct URLSession client for YouTube Data API v3.
- No Alamofire, Firebase, Supabase, React Native, Expo, YouTube WebView player, or backend in V1.
- Windows is the authoring/orchestration host; macOS CI is the Apple build/test plane.
- XcodeGen owns project generation; generated `.xcodeproj` state is not committed.
- Shorts are hard-disabled. No Shorts tab/shelf, `/shorts/` route, vertical swipe player, or implicit autoplay-next.

If real evidence makes a locked decision impossible, create an ADR proposal and mark only the affected path blocked. Do not silently rewrite architecture.

## Autonomy directive

The default behavior inside an **active, justified** campaign is continue, not ask. Outside an active campaign, the default is truthfully stop rather than invent work.

An agent may autonomously:

- execute work already authorized by an ACTIVE execution prompt;
- repair newly evidenced Critical/High regressions immediately;
- diagnose and fix CI/build failures caused by project code/configuration;
- add deterministic tests/test seams required by a real defect;
- update docs/state/checkpoints to match verified reality;
- respond to owner-reported device failures when the root cause is agent-actionable.

Do not create speculative features, broad cleanup waves, or another hardening campaign simply because owner validation is still pending.

## True stop conditions

Stop the affected path when one of these is true:

1. there is no active agent-actionable campaign and no new evidence-backed defect;
2. a required secret/account action cannot be safely synthesized or mocked;
3. Apple signing or physical-device action is required and no automated environment can perform it;
4. an upstream dependency is demonstrably broken and there is no compliant local fix;
5. two repository specifications materially contradict each other and precedence rules cannot resolve them;
6. satisfying the work requires changing a locked architectural decision;
7. continuing would risk credential exposure, destructive data loss, or irreversible repository damage.

When an active campaign is blocked, record the blocker precisely in `.agent/STATE.yaml`, add evidence, continue independent unblocked work, and only then escalate if nothing useful remains. When only owner validation remains, do not misclassify that as unfinished engineering.

## Current validation handoff

`DEVICE_VALIDATION_V1_REFRESHED` is intentionally owner-executed. Required evidence is:

- physical iPhone Batch A A1–A14 against code SHA `7a70943`;
- one authenticated opt-in live-smoke dispatch;
- repair/requalification only if either produces a real defect.

Never invent run IDs, screenshots, device outcomes, credentials, or live-service results. The terminal product-validation state is reached only when the owner evidence exists.