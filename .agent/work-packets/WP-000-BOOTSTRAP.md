# WP-000-BOOTSTRAP — Prove the Autonomous Apple Build/Test Loop

**Campaign:** IMPLEMENTATION_V1  
**Milestone/Gate:** M0 / G0  
**Status at documentation baseline:** ready; Apple-side evidence not yet observed.

## Objective

Prove that a Windows-authored FocusTube repository can be generated, built, launched, and UI-smoke-tested automatically on remote macOS/Xcode/iOS Simulator. This is infrastructure for every later packet.

## Preconditions already present

- root `project.yml` exists for XcodeGen;
- `Package.swift`/FocusTubeCore scaffold exists;
- SwiftUI shell/root tabs exist;
- GitHub Actions/macOS CI scaffold exists;
- initial core policy tests were observed passing in the artifact-construction environment;
- bootstrap commit on main: `81384e84127177186eaa9f87f71a36874f47b785`.

Do not assume CI passed merely because workflow files exist.

## Execution sequence

### W1 — Local/platform-neutral baseline

1. inspect repository status and current branch;
2. run `swift --version` where available;
3. run `swift test`;
4. if Windows Swift is unavailable in the current agent environment, record that fact and rely on CI for this criterion rather than blocking all work;
5. fix project-owned core test failures before Apple work.

### W2 — Inspect Apple CI definition

Verify the workflow/scripts:

- select supported macOS runner/toolchain;
- install/select XcodeGen;
- generate from `project.yml` without committing `.xcodeproj`;
- list/discover available simulator runtimes/devices;
- build/test against an available compatible iPhone simulator;
- retain useful xcresult/log/screenshot artifacts;
- print Xcode/Swift/XcodeGen/runtime/device versions.

Avoid brittle hard-coding to a simulator that may not be present on the runner image.

### W3 — Run Apple build plane

Trigger/observe the repository's normal CI path by pushing the implementation checkpoint according to the agent's execution environment.

Required observed stages:

```text
checkout
 -> toolchain info
 -> XcodeGen
 -> package resolution
 -> iOS build/test
 -> simulator boot/install/launch
 -> LaunchTests/root tabs
 -> artifacts
```

### W4 — Diagnose failures, do not blind-retry

Classify first failure:

- Xcode/XcodeGen syntax -> fix project/config;
- package-resolution/version mismatch -> confirm pinned/current documented dependency assumptions;
- missing runtime/device -> improve discovery/selection script;
- compile error -> fix source/project settings;
- simulator boot/install issue -> inspect simctl state/logs and retry once only if demonstrably transient;
- UI test mismatch -> inspect launch/screenshot/accessibility identifiers and fix app/test;
- GitHub Actions permission/config problem -> record exact smallest external action if not solvable from repository.

### W5 — Record G0 evidence

When successful, record:

- `swift test` result/environment;
- CI workflow/run/job identifiers if available;
- Xcode version;
- Swift version;
- XcodeGen version;
- selected iOS runtime/device;
- app build result;
- LaunchTests result;
- artifact names/locations.

Create a checkpoint via `.agent/CHECKPOINT_PROTOCOL.md`.

## Acceptance

Every G0 criterion in `docs/14-ACCEPTANCE-GATES.md` has observed evidence.

Then update:

```text
WP-000 = complete
M0 = complete
G0 = pass
current packet = WP-001-EXTRACTION
current milestone = M1_MEDIA_VIABILITY
```

Immediately continue WP-001. Do not wait for user acknowledgement.

## Forbidden shortcuts

- Do not commit generated `FocusTube.xcodeproj/` merely to avoid fixing XcodeGen.
- Do not disable LaunchTests to get a green workflow.
- Do not mark G0 passed from YAML review/code inspection alone.
- Do not switch to a cross-platform framework to avoid macOS CI.
- Do not add a permanent Mac/backend requirement; remote macOS CI remains the build plane unless an ADR changes it.