# 08 — Windows-First / Remote iOS Development

## Constraint

The primary authoring machine is Windows. Native iOS build and Apple Simulator execution require macOS/Xcode. The solution is a split development plane, not an attempt to emulate iOS locally on Windows.

## Windows plane

Install the official Swift Windows toolchain and run:

```powershell
swift --version
swift test
```

`FocusTubeCore` must remain buildable here. This gives the coding agent fast deterministic feedback for domain logic.

Swift.org currently documents WinGet-based installation and VS Code support. Use stable Swift, not development snapshots, unless a specific blocker requires otherwise.

## Apple build plane

GitHub Actions `macos-26` is the initial remote Mac.

Responsibilities:

- install/use XcodeGen;
- generate `FocusTube.xcodeproj` from `project.yml`;
- resolve Swift packages;
- build iOS app;
- boot/select an available iPhone Simulator;
- run XCUITest;
- capture screenshots/logs/xcresult artifacts;
- later run live media smoke tests.

Target stable toolchain family:

- macOS 26 runner;
- Xcode 26.6 when present;
- otherwise an explicitly accepted Xcode 26.x fallback reported in CI logs;
- no Xcode 27 beta as a normal dependency.

## Why XcodeGen

A hand-edited `.pbxproj` is a poor source format for an agent operating primarily on Windows. XcodeGen keeps project structure in human-readable YAML, generates the project on demand, supports SPM dependencies, and avoids generated-project merge conflicts.

`project.yml` is authoritative; `FocusTube.xcodeproj` is disposable.

## Simulator selection

CI must discover available runtimes/devices instead of hard-coding one exact simulator model/runtime that may disappear from a runner image.

Preferred sequence:

1. `xcodebuild -version`;
2. `xcrun simctl list runtimes`;
3. `xcrun simctl list devices available`;
4. select an available iPhone device on an iOS 26.x runtime when possible;
5. boot it;
6. run tests by UDID.

## Agent autonomy loop

```text
Windows agent edits
 -> swift test
 -> commit/push
 -> GitHub macOS workflow
 -> xcodegen generate
 -> build/test/simulator
 -> upload artifacts
 -> agent inspects failure/evidence
 -> fix/repeat
```

The user should not manually click through every development iteration.

## What still requires physical iPhone validation

Simulator coverage is not a final substitute for hardware. Milestone/release gates should occasionally validate:

- background behavior under real suspension;
- PiP on the user's device;
- lock-screen/remote command behavior;
- Bluetooth/audio interruptions;
- actual storage pressure;
- real Wi-Fi/cellular transitions;
- YouTubeKit behavior on device networking/codec hardware.

This physical-device work is a milestone gate, not a per-commit task.
