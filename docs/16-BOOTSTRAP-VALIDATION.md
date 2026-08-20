# 16 — Bootstrap Validation Record

Validation performed while constructing the initial repository payload on 2026-08-20.

## Passed

- `project.yml` parses as valid YAML.
- `.agent/STATE.yaml` parses as valid YAML.
- `swift test` builds FocusTubeCore with Swift 6.2.1 on x86_64 Linux and passes all 5 initial tests.
- Initial tests prove the fixed download ladder `[1080, 720, 480, 360]`, hard 1080p ceiling, omission of unavailable qualities, conservative 180-second short-form boundary, and `/shorts/` route block.
- CI shell scripts pass static shell syntax validation.

## Not yet proven

The construction environment is not macOS, so the following must be proven by WP-000 on GitHub `macos-26`:

- XcodeGen 2.46+ accepts `project.yml`;
- YouTubeKit 0.4.8 and GoogleSignIn 9.0.0 resolve under Xcode 26.x;
- FocusTube iOS target compiles;
- iOS Simulator boots and launches FocusTube;
- XCUITest `LaunchTests` passes.

Do not mark G0 complete until those Apple-side items are evidenced.
