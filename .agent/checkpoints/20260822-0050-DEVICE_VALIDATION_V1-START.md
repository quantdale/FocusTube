# Checkpoint — DEVICE_VALIDATION_V1 START

- Campaign: DEVICE_VALIDATION_V1
- Milestone/Gate: entry at DV-0
- Packet: DV-0-RELEASE-BASELINE (in progress)
- State: partial (campaign opened; baseline audits beginning)
- Commit: 47e1126 (HEAD; code baseline 03ce6f6)

## Mission

Take FocusTube from `personal_release_candidate` to
`personal_release_validated` (or
`personal_release_validated_with_deferred_device_evidence`, only with
itemized unavoidable external deferrals) by:

1. preparing the project for real iPhone installation;
2. minimizing owner manual actions to one compact validation batch;
3. validating real Google OAuth configuration;
4. validating real iPhone runtime, media, download, background behavior;
5. fixing every agent-actionable defect found;
6. re-running CI after every remediation and recording run IDs;
7. synchronizing durable state and producing the final validation report.

This is NOT a feature campaign. Locked requirements (native iOS, YouTubeKit
local-only extraction, 1080/720/480/360 exact-quality ladder, Shorts hard
disabled) are invariants.

## Work packets

| ID   | Name                                  | Kind            |
|------|---------------------------------------|-----------------|
| DV-0 | Release baseline verification         | automated       |
| DV-1 | Apple signing/install preparation     | automated+owner |
| DV-2 | Google OAuth configuration            | automated+owner |
| DV-3 | Real account functional validation    | device/owner    |
| DV-4 | Real media playback/download          | device/owner    |
| DV-5 | Offline/download durability           | device/owner    |
| DV-6 | Background/PiP/system-media           | device/owner    |
| DV-7 | Lifecycle/network/storage             | device/owner    |
| DV-8 | Remediation loop                      | automated       |
| DV-9 | Final release validation + report     | mixed           |

Rules: automate everything possible BEFORE asking the owner; consolidate
unavoidable physical actions into ONE numbered batch with exact evidence to
return; never fake device evidence; classify anything untestable as
`external_validation_unavailable` with reason.

## Baseline verified at campaign open

- HEAD 47e1126 = docs commit on top of validated code commit 03ce6f6.
- Worktree clean; origin/main in sync.
- STATE terminal state was `personal_release_candidate`; no open Critical/High
  or Medium/Low items (HARDENING_BACKLOG fully dispositioned).
- Authoritative observed CI values (all via api.github.com on 2026-08-22):
  - commit 03ce6f6 (code): Core Tests run 32501838807 SUCCESS;
    iOS CI run 32501839603 SUCCESS (job 96833085436; Build/Unit/UI/Gate green).
  - commit 47e1126 (docs-only, campaign-open HEAD): Core Tests run
    32503653009 SUCCESS; iOS CI run 32503652704 IN_PROGRESS at campaign open —
    must be observed green before DV-0 closes.

## Acceptance evidence

- See baseline list above; all values observed via api.github.com on
  2026-08-22 by the campaign-opening agent.

## Known failures or deferred items

- Local Windows Swift toolchain cannot link (missing MSVC CRT import libs);
  deterministic Core validation runs on macOS CI. Recorded, not hidden.
- All device/account evidence pending owner batch (DV-3..DV-7).

## Exact next waypoint

- DV-0: audit bundle id / entitlements / Info.plist / URL schemes / background
  modes / signing settings / OAuth plumbing / Release config / secrets; repair
  agent-actionable gaps; observe iOS CI green on 47e1126; then prepare
  DV-1/DV-2 owner instructions.

## Resume commands

```bash
git fetch origin && git pull --ff-only origin main
cat .agent/STATE.yaml   # live pointer: current_work_packet
```
