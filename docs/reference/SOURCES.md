# Research Source Register

Research baseline: **2026-08-20**. Agents must re-verify time-sensitive assumptions before dependency/toolchain upgrades.

## YouTubeKit

- Repository: https://github.com/alexeichhorn/YouTubeKit
  - direct stream extraction for Apple platforms;
  - filters for exact resolution, audio/video track composition, native playability;
  - optional local/remote extraction methods;
  - project warning that it is a work in progress and may not work in every region.
- Releases: https://github.com/alexeichhorn/YouTubeKit/releases
  - verified discoverable latest release at research time: **0.4.8**;
  - recent release notes repeatedly mention fixes for YouTube extraction changes, confirming upstream fragility.

## Apple

- iOS simulator / physical-device testing:
  https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices
- Background downloads:
  https://developer.apple.com/documentation/foundation/downloading-files-in-the-background
- Background URLSession configuration:
  https://developer.apple.com/documentation/foundation/urlsessionconfiguration/background(withidentifier:)
- AVPlayerViewController:
  https://developer.apple.com/documentation/avkit/avplayerviewcontroller
- Picture in Picture standard player:
  https://developer.apple.com/documentation/avkit/adopting-picture-in-picture-in-a-standard-player
- Xcode 26.6 release:
  https://developer.apple.com/news/releases/?id=06252026a

## Swift on Windows

- https://www.swift.org/install/windows/
  - stable Swift toolchain installation on Windows via WinGet/manual paths;
  - VS Code/SourceKit-LSP workflow.

## XcodeGen

- Repository: https://github.com/yonaskolb/xcodegen
- Project spec: https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md
  - YAML/JSON-generated Xcode projects;
  - SPM package dependencies;
  - exact-version package pinning;
  - generated project can stay out of Git.
- Research-time README references XcodeGen 2.46.0 as current dependency example/minimum candidate.

## GitHub Actions

- Hosted runner selection:
  https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job
  - `macos-26` available as a standard macOS hosted-runner label at research time.

## Google Sign-In

- iOS/macOS integration:
  https://developers.google.com/identity/sign-in/ios/start-integrating
  - Swift Package Manager package `GoogleSignIn-iOS`;
  - documented version 9.0.0 at research time;
  - GoogleSignIn and GoogleSignInSwift products.

## YouTube Data API

- Overview/quota:
  https://developers.google.com/youtube/v3/getting-started
- Search list:
  https://developers.google.com/youtube/v3/docs/search/list
- Quota calculator:
  https://developers.google.com/youtube/v3/determine_quota_cost
- Subscriptions list:
  https://developers.google.com/youtube/v3/docs/subscriptions/list
- Subscriptions insert:
  https://developers.google.com/youtube/v3/docs/subscriptions/insert
- Comment threads insert:
  https://developers.google.com/youtube/v3/docs/commentThreads/insert
- Comments insert/list:
  https://developers.google.com/youtube/v3/docs/comments/insert
  https://developers.google.com/youtube/v3/docs/comments/list

Current documented quota architecture includes 100 default `search.list` calls/day in a granular search bucket and 10,000 units/day across most other endpoints.

## YouTube developer-policy warning

- https://developers.google.com/youtube/terms/developer-policies-guide
  - explicitly warns API clients against offline downloads outside the YouTube Premium experience and other prohibited media transformations.

## Verification rule

When a source is version-sensitive (YouTubeKit, Xcode, XcodeGen, GoogleSignIn, GitHub runner image), verify current official/primary-source state before changing pins. Do not update a dependency merely because a newer semantic version exists; run the relevant FocusTube regression gates first.
