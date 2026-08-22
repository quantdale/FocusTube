# FocusTube

FocusTube is a personal-use, native iOS YouTube client designed around intentional long-form viewing rather than short-form engagement loops.

The V1 product focuses on subscriptions/Home, deliberate search, native video playback, comments/account actions, downloads, and a local offline library. Shorts, the vertical swipe player, creator tools, shopping, and recommendation-driven rabbit holes are intentionally absent.

> **Status:** `device_validation_in_progress` — implementation, HARDENING_V1 backlog closure, and the HARDENING_V2 adversarial pass are all complete with green CI on commit `2c7646d` (Core Tests run 32584881846; iOS CI run 32584881870: Build success, unit tests 75 executed / 0 failures, UI tests 1 / 0 failures, Gate success). Remaining work is consolidated owner-side device/account validation in [DEVICE_VALIDATION_BATCH_A.md](DEVICE_VALIDATION_BATCH_A.md). Live progress pointer: [`.agent/STATE.yaml`](.agent/STATE.yaml). Fresh coding agents start with [`START_HERE.md`](START_HERE.md).

## Autonomous development mode

This repository contains a durable control plane so an AI coding agent can execute the V1 implementation with minimal supervision:

- [`START_HERE.md`](START_HERE.md) — recovery/entry point.
- [`AGENTS.md`](AGENTS.md) — non-negotiable engineering/autonomy contract.
- [`.agent/STATE.yaml`](.agent/STATE.yaml) — current status, active packet, exact next waypoint, evidence/blockers.
- [`.agent/WAYPOINTS.yaml`](.agent/WAYPOINTS.yaml) — machine-readable packet dependencies/status.
- [`.agent/AUTONOMOUS_EXECUTION.md`](.agent/AUTONOMOUS_EXECUTION.md) — continuous execution algorithm.
- [`.agent/BOOT_PROMPT.md`](.agent/BOOT_PROMPT.md) — minimal prompt for a fresh agent.
- [`.agent/checkpoints/`](.agent/checkpoints/) — durable gate/milestone evidence.
- [`.agent/HARDENING_BACKLOG.md`](.agent/HARDENING_BACKLOG.md) — nonblocking debt intentionally deferred during implementation.

The active campaign is **DEVICE_VALIDATION_V1**: INTEGRATION_COMPLETION_V1 and the HARDENING_V1/V2 passes are complete (H2-EXIT evidence on `2c7646d`); what remains is owner-executed physical-device validation plus one opt-in live-smoke dispatch. Agents keep CI green and diagnose/repair any device-reported failures.

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
Read START_HERE.md and follow the repository's durable state. Keep DEVICE_VALIDATION_V1 moving: CI green, diagnose/repair any owner-reported device failures, record evidence/checkpoints, and never claim unobserved evidence.
```

For the exact reusable prompt, use [`.agent/BOOT_PROMPT.md`](.agent/BOOT_PROMPT.md).

## Current external assumptions

The bootstrap research baseline (2026-08-20) records YouTubeKit 0.4.8, GoogleSignIn 9.0.0 documentation, Swift-on-Windows support, and Xcode 26.6 as the targeted stable Apple toolchain. Reverify external assumptions when a packet actually depends on them; do not churn dependencies without evidence. See [`docs/reference/SOURCES.md`](docs/reference/SOURCES.md).

## Policy note

FocusTube's custom extraction/download path is not the official YouTube offline-playback path. Keep official YouTube Data API interactions separate from the unofficial media-extraction subsystem and do not represent the latter as officially authorized. See [`docs/11-SECURITY-PRIVACY-POLICY.md`](docs/11-SECURITY-PRIVACY-POLICY.md).