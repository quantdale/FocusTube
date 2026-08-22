# Checkpoint — HARDENING_V2 START

- Campaign: HARDENING_V2 (temporary autonomous campaign)
- Suspended: DEVICE_VALIDATION_V1 (awaiting owner device evidence; restored on exit)
- Packet: H2-W1 verify seed findings + adversarial audit
- State: partial (campaign opened; verification wave launching)
- Commit: 4a7903f (baseline, both CI workflows observed green:
  Core Tests 32533244518, iOS CI 32533244458)

## Mission

Adversarial production-hardening of the entire codebase while
DEVICE_VALIDATION_V1 waits for the owner's physical iPhone. No features,
no architecture changes, no fake device claims. Exit gate H2-EXIT: no known
Critical/High agent-actionable defects, all automated gates green, seed
findings resolved or refuted with evidence, policy invariants intact.

## Seed hypotheses to VERIFY before patching

H2-001 GoogleSignIn configure race (fixed-500ms sleep coordination)
H2-002 rapid video selection stale-extraction race in PlayerCoordinator
H2-003 playback stall watchdog may never fire (no timer, callback-driven only)
H2-004 playLocalFile stale metadata/state from prior online item
H2-005 reattached background-event ordering through per-event MainActor Tasks
H2-006 staging-move failure falls back to ephemeral temp URL as completion
H2-007 DownloadService single lastFailure couples concurrent downloads
H2-008 try? fetch masquerading as empty database
H2-009 background completion registers title=videoID (metadata loss)
H2-010 allowsCellularAccess=true contradicts docs/03 default-off spec
H2-011 no logical max-concurrent-downloads(2) admission control
H2-012 retry policy scattered vs one bounded explicit policy
H2-013 try? audio-session configuration swallowed
H2-014 silent try?/catch{} filesystem operations sweep

Plus whole-codebase adversarial audit (concurrency, AVFoundation lifecycle,
SwiftData, filesystem, auth, API client, UI, Shorts firewall, quality ladder,
security) and CI gate truthfulness review.

## Constraints

- Local Windows toolchain cannot link → validation = macOS CI only.
  Workers must mirror existing patterns exactly; coordinator integration-reviews
  every diff before push.
- ios-ci uses cancel-in-progress concurrency → batch coherent fixes into few
  commits; observe final run IDs.
- Locked invariants unchanged (YouTubeKit local-only, 1080/720/480/360 exact,
  Shorts hard-disabled, SwiftData+filesystem, background URLSession).

## Exact next waypoint

- Launch disjoint read-only verification workers over seed findings + areas;
  integrate verified findings into a severity-ranked fix plan.

## Resume commands

```bash
git fetch origin && git pull --ff-only origin main
cat .agent/STATE.yaml   # active_campaign HARDENING_V2
```
