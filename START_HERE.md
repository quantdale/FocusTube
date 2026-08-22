# START HERE — FocusTube Autonomous Implementation Entry Point

FocusTube is designed to be executable by a fresh AI coding agent with **zero chat history and minimal human supervision**. Repository state, not conversation memory, is authoritative.

## Mission

Build the complete V1 implementation of FocusTube: a personal native iOS YouTube client for deliberate long-form viewing, with native playback, comments/account features, and first-class offline downloads, while structurally excluding Shorts and short-form consumption mechanics.

The implementation campaign is continuous. **Do not stop after one task or one work packet.** Finish the active packet, validate it, checkpoint it, advance the durable state, select the next unblocked packet, and continue until the implementation-campaign exit gate is reached or a true stop condition exists.

## Current campaign

- Campaign: `DEVICE_VALIDATION_V1` (active; restored after HARDENING_V2 exit)
- Scope: owner-executed physical-device/account validation (Batch A items A1–A14, Part 0 setup) plus one opt-in live-smoke dispatch. All agent-actionable engineering — implementation M0–M8, HARDENING_V1 backlog closure, and the HARDENING_V2 adversarial pass — is complete with green CI on `2c7646d` (Core Tests run 32584881846; iOS CI run 32584881870).
- Agent role while waiting: keep CI green, diagnose/repair any owner-reported device failures (DV-8), record evidence.
- Nonblocking Medium/Low cleanup still goes to `.agent/HARDENING_BACKLOG.md` (currently zero open items); Critical/High is fixed immediately.

## Mandatory reading order

Before making changes in a fresh session, read in this exact order:

1. `START_HERE.md`
2. `AGENTS.md`
3. `.agent/STATE.yaml`
4. `.agent/AUTONOMOUS_EXECUTION.md`
5. `.agent/WAYPOINTS.yaml`
6. `.agent/OPERATING_CONTRACT.md`
7. `.agent/STATE_MACHINE.md`
8. current packet under `.agent/work-packets/`
9. subsystem docs referenced by that packet
10. `docs/14-ACCEPTANCE-GATES.md`
11. `docs/16-IMPLEMENTATION-CAMPAIGN.md`

Only read the entire documentation set when a decision actually spans multiple subsystems. Prefer targeted context over repeatedly rereading every file.

## Five-minute recovery algorithm

A fresh agent must be able to resume with this algorithm:

1. `git status --short --branch` and inspect the current HEAD.
2. Read `.agent/STATE.yaml` and `.agent/WAYPOINTS.yaml`.
3. If the worktree contains changes, determine whether they are documented in state/checkpoint notes before touching them. Do not discard unknown work.
4. Read the active work packet.
5. Inspect the implementation/tests relevant to its acceptance criteria.
6. Run the cheapest deterministic baseline available in the current environment.
7. Continue from `current_waypoint`, not from the beginning of the project.
8. After the packet passes, update state and immediately continue to the next packet.

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

The default behavior is **continue, not ask**.

The agent may autonomously:

- implement planned V1 functionality;
- refactor locally when required to satisfy the active packet;
- add deterministic tests and test seams;
- repair CI/build failures caused by project code/configuration;
- update docs/state/checkpoints to match verified reality;
- fix Critical/High bugs immediately;
- defer nonblocking Medium/Low cleanup to the hardening backlog;
- advance from one packet to the next when its gate evidence passes.

Do **not** pause for subjective confirmation about naming, minor UI details, file organization, or implementation choices already constrained by the specs. Choose the simplest maintainable option consistent with the architecture.

## True stop conditions

Stop the affected path only when one of these is true:

1. a required secret/account action cannot be safely synthesized or mocked;
2. Apple signing or physical-device action is required and no automated environment can perform it;
3. an upstream dependency is demonstrably broken and there is no compliant local fix;
4. two repository specifications materially contradict each other and precedence rules cannot resolve them;
5. satisfying the packet requires changing a locked architectural decision;
6. continuing would risk credential exposure, destructive data loss, or irreversible repository damage.

When stopped, record the blocker precisely in `.agent/STATE.yaml`, add evidence, continue any independent unblocked work, and only then request human input if nothing useful remains.

## Continuous execution loop

```text
RECOVER STATE
    -> SELECT ACTIVE WAYPOINT
    -> INSPECT CODE + TESTS
    -> IMPLEMENT SMALLEST COHERENT SLICE
    -> LOCAL DETERMINISTIC VALIDATION
    -> REMOTE APPLE VALIDATION when required
    -> FIX FAILURES
    -> RECORD EVIDENCE
    -> CHECKPOINT
    -> ADVANCE STATE
    -> NEXT WAYPOINT
    -> repeat until IMPLEMENTATION_COMPLETE
```

A claim such as "should work" is never evidence. Evidence is an observed command result, test result, CI run, simulator launch, screenshot/artifact, or device-validation record.

## Initial technical priority

Do not spend significant effort on UI polish before proving the media path:

```text
YouTube video ID
  -> YouTubeKit local extraction
  -> allowed stream normalization {1080,720,480,360}
  -> native AVPlayer playback
  -> background download
  -> native adaptive mux when required
  -> validated local file
  -> offline AVPlayer playback
```

## Windows baseline

From Windows, use the platform-neutral package whenever possible:

```powershell
swift --version
swift test
```

SwiftUI/AVKit/AVFoundation/SwiftData/GoogleSignIn behavior must be validated through macOS/Xcode CI. See `docs/08-WINDOWS-REMOTE-IOS-DEVELOPMENT.md`.

## End condition for this campaign

The campaign ends when DEVICE_VALIDATION_BATCH_A items A1–A14 pass with owner evidence and one live-smoke dispatch result is recorded (DV-EXIT). The terminal durable state is `personal_release_validated`. If a genuine external blocker appears instead, state becomes `implementation_complete_external_validation_required` with the blocker recorded in `.agent/STATE.yaml`.