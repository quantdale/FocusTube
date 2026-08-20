# ADR-0003 — XcodeGen as Project Source of Truth

**Status:** Accepted

## Decision

Commit `project.yml`; generate `.xcodeproj` on macOS; do not commit generated Xcode project state.

## Rationale

The primary authoring machine is Windows and the development workflow is agent-heavy. Human-readable declarative project configuration is materially easier to review, modify, and reproduce remotely than pbxproj state.
