# 10 — CI/CD

## Goals

- make Apple-only validation available to a Windows-based agent;
- make project generation reproducible;
- make failures inspectable through logs and artifacts;
- avoid dependence on a persistent paid Mac until needed.

## Initial workflows

### `core.yml`

Runs cross-platform/core checks. It may start on macOS for simplicity and later add Windows-native Swift CI once setup reliability is proven.

### `ios-ci.yml`

On push/PR/manual dispatch:

1. checkout;
2. select approved Xcode 26.x, preferring 26.6;
3. install XcodeGen;
4. `xcodegen generate`;
5. `swift test`;
6. resolve Xcode SPM packages;
7. select/boot simulator dynamically;
8. run app/UI tests with `xcodebuild`;
9. collect `.xcresult`, logs, screenshots.

## Generated project rule

Do not commit generated `FocusTube.xcodeproj`. CI creates it every run.

## Toolchain drift

Runner images change. The workflow must log:

- macOS version;
- Xcode version;
- Swift version;
- XcodeGen version;
- installed iOS runtimes;
- selected simulator model/UDID.

If exact Xcode 26.6 is absent, the job may use another accepted stable Xcode 26.x only when the project remains compatible. Do not silently use a beta toolchain.

## Live-media workflow

Add after M1 implementation. Run on manual dispatch and a low-frequency schedule. Do not block unrelated pull requests solely because upstream extraction has broken; surface it as a distinct health signal.

## Physical-device distribution

Not required for bootstrap. When ready, choose the lowest-friction personal-device signing/distribution path consistent with the user's Apple account. Keep signing secrets out of repository contents and normal logs.
