# WP-000-BOOTSTRAP

**Milestone/Gate:** M0 / G0

## Objective

Create a reproducible Windows-authored, macOS-built iOS shell.

## Required work

- Verify `swift test` passes for FocusTubeCore on Windows/stable Swift.
- Validate `project.yml` with XcodeGen on macOS.
- Generate `FocusTube.xcodeproj` without committing it.
- Resolve YouTubeKit 0.4.8 and GoogleSignIn 9.0.0.
- Build FocusTube for an available iOS Simulator.
- Run `LaunchTests` and capture result bundle.
- Add/repair GitHub Actions workflow and simulator-selection script.
- Record toolchain versions and selected simulator.

## Acceptance

- G0 fully passes.
- `.agent/STATE.yaml` advances to WP-001.
- No generated project committed.

## Rules

- Preserve all locked decisions in `START_HERE.md` and `AGENTS.md`.
- Add/update deterministic tests with behavior changes.
- Record exact validation evidence in `.agent/STATE.yaml`.
- Do not advance the packet merely on code inspection.
