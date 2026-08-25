# FocusTube

FocusTube is a personal-use, native iOS YouTube client designed around intentional long-form viewing rather than short-form engagement loops.

The V1 product focuses on subscriptions/Home, deliberate search, native video playback, comments/account actions, downloads, and a local offline library. Shorts, the vertical swipe player, creator tools, shopping, and recommendation-driven rabbit holes are intentionally absent.

> **Status:** `hardening_v3_complete_device_validation_pending` — implementation M0–M8, SPEC_CLOSURE_DAILY_DRIVER_V2, and HARDENING_V3 are complete. `H3-EXIT` passed on qualified code SHA `7a70943`; Core Tests run `32891558919` and iOS CI run `32891558884` were successful at that code SHA, including the fail-closed Gate and journeys 20/20. The later `main` commits through `f1dcca` are durable-state/docs evidence only; their latest Core Tests (`32898272247`) and iOS CI (`32898272210`) runs are also green.
>
> The next required work is **owner-only** `DEVICE_VALIDATION_V1_REFRESHED`: physical-iPhone Batch A A1–A14 plus one authenticated opt-in live-smoke dispatch against `7a70943`. The 2026-08-26 planner audit found no legitimate next agent-side coding campaign: the hardening backlog is closed, H3-07 found no residual Critical/High defects, and there are no open GitHub issues/PRs. Do not manufacture another campaign without new evidence-backed defects or a new product directive.

## Autonomous development mode

This repository contains a durable control plane so an AI coding agent can recover state without relying on chat history:

- [`START_HERE.md`](START_HERE.md) — recovery/entry point.
- [`AGENTS.md`](AGENTS.md) — non-negotiable engineering/autonomy contract.
- [`.agent/PLANNER_HANDOFF.md`](.agent/PLANNER_HANDOFF.md) — planner/executor boundary.
- [`.agent/EXECUTION_PROMPT.md`](.agent/EXECUTION_PROMPT.md) — current/most-recent campaign prompt and status.
- [`.agent/STATE.yaml`](.agent/STATE.yaml) — current status, waypoint, evidence, and blockers.
- [`.agent/WAYPOINTS.yaml`](.agent/WAYPOINTS.yaml) — machine-readable campaign history/status.
- [`.agent/AUTONOMOUS_EXECUTION.md`](.agent/AUTONOMOUS_EXECUTION.md) — continuous execution algorithm.
- [`.agent/BOOT_PROMPT.md`](.agent/BOOT_PROMPT.md) — minimal prompt for a fresh agent.
- [`.agent/checkpoints/`](.agent/checkpoints/) — durable gate/milestone evidence.
- [`.agent/HARDENING_BACKLOG.md`](.agent/HARDENING_BACKLOG.md) — hardening debt ledger; HB-015..HB-030 are resolved by H3.

There is currently **no active agent-actionable coding campaign**. The last execution prompt, `HARDENING_V3_SYSTEMIC_DEBT_CLOSURE`, is `Status: COMPLETE`. A fresh agent should reconcile repository truth, then stop if no new evidence-backed defect exists. The downstream gate is owner-executed device/account validation.

## Locked product/technical decisions

- Native iOS app, not a WebView wrapper.
- SwiftUI UI with AVPlayer/AVPlayerViewController.
- YouTubeKit is the only media extractor; **local extraction only**.
- No yt-dlp fallback and no remote extractor.
- Download resolutions are exactly **1080p, 720p, 480p, 360p**; 1080p is the hard ceiling.
- Offline downloads are a first-class requirement.
- URLSession background transfer + native AVFoundation muxing path.
- YouTube Data API v3 for supported account-aware metadata/actions; GoogleSignIn for OAuth.
- SwiftData indexes metadata; filesystem stores media.
- No backend for core V1.
- Windows-first authoring; remote macOS/Xcode/iOS Simulator build/test plane.
- XcodeGen generates the Xcode project; generated `.xcodeproj` is not committed.
- Shorts are hard-blocked; no vertical swipe feed.
- Autoplay-next and infinite scrolling are off by default.

## Repository map

```text
FocusTube/
├── START_HERE.md
├── AGENTS.md
├── project.yml
├── Package.swift
├── App/
├── Sources/FocusTubeCore/
├── Tests/FocusTubeCoreTests/
├── FocusTubeUITests/
├── docs/
├── .agent/
│   ├── PLANNER_HANDOFF.md
│   ├── EXECUTION_PROMPT.md
│   ├── STATE.yaml
│   ├── WAYPOINTS.yaml
│   ├── AUTONOMOUS_EXECUTION.md
│   ├── CHECKPOINT_PROTOCOL.md
│   ├── HARDENING_BACKLOG.md
│   ├── checkpoints/
│   └── work-packets/
├── scripts/ci/
└── .github/workflows/
```

## Starting an agent

The short version is:

```text
Read START_HERE.md and the durable agent state. If EXECUTION_PROMPT is ACTIVE, reconcile and execute it. If it is COMPLETE and STATE says only owner validation remains, do not invent work; report the owner-only DEVICE_VALIDATION_V1_REFRESHED gate unless new evidence proves an agent-actionable regression.
```

For the exact reusable prompt, use [`.agent/BOOT_PROMPT.md`](.agent/BOOT_PROMPT.md).

## Current external assumptions

The bootstrap research baseline records YouTubeKit 0.4.8, GoogleSignIn 9.0.0 documentation, Swift-on-Windows support, and Xcode 26.6 as the targeted stable Apple toolchain. Reverify external assumptions when work actually depends on them; do not churn dependencies without evidence. See [`docs/reference/SOURCES.md`](docs/reference/SOURCES.md).

## Policy note

FocusTube's custom extraction/download path is not the official YouTube offline-playback path. Keep official YouTube Data API interactions separate from the unofficial media-extraction subsystem and do not represent the latter as officially authorized. See [`docs/11-SECURITY-PRIVACY-POLICY.md`](docs/11-SECURITY-PRIVACY-POLICY.md).