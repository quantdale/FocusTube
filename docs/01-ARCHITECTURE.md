# 01 — Architecture

## Architectural shape

FocusTube uses a feature-oriented native architecture with a small cross-platform domain core and isolated Apple/Google/YouTube integration adapters.

```text
SwiftUI Features
      |
      v
Application coordinators / view models (@MainActor)
      |
      +----------------------+-----------------------+
      |                      |                       |
      v                      v                       v
PlaybackCoordinator   DownloadManager actor   YouTubeAPIClient actor
      |                      |                       |
      v                      v                       v
MediaExtracting       URLSession background   URLSession + Codable
      |
      v
YouTubeKitMediaExtractor
      |
      v
YouTubeKit (.local only)
```

## Layer rules

### FocusTubeCore

Cross-platform, deterministic domain logic only. It must compile with the Swift Windows toolchain.

Allowed concerns:

- download quality policy;
- short-form policy;
- feed merge/sort/filter logic;
- state-machine definitions;
- API-neutral domain models;
- retry/backoff decision logic;
- quota policy;
- storage sizing calculations;
- URL/video-ID parsing that does not require Apple frameworks.

Forbidden imports include SwiftUI, UIKit, AVKit, AVFoundation, SwiftData, StoreKit, GoogleSignIn, and YouTubeKit.

### App layer

SwiftUI composition, navigation, @Observable state, dependency wiring, settings, screen models.

### Media layer

Apple-specific playback/download/filesystem/muxing plus one YouTubeKit adapter. No feature screen may import YouTubeKit directly.

### YouTube account layer

Google OAuth and direct YouTube Data API v3 requests. Account API behavior must remain independent of media extraction.

## Concurrency

- UI-facing observable state: `@MainActor`.
- DownloadManager: actor.
- YouTubeAPIClient: actor.
- Media extraction orchestration: actor unless the library proves incompatible.
- Filesystem mutations: actor or otherwise serialized behind MediaFileStore.
- Do not share mutable URLSession delegate state without synchronization.

## Dependency injection

Protocol boundaries are mandatory for:

- `MediaExtracting`;
- `YouTubeAPIProviding`;
- `AuthenticationProviding`;
- `DownloadTransporting` when practical;
- `MediaFileStoring`;
- clock/date provider for deterministic tests.

Production wiring lives in one composition root. UI tests use fixture providers through launch arguments/environment.

## Project generation

`project.yml` is the source of truth for Xcode project structure. XcodeGen generates `FocusTube.xcodeproj` on macOS. The generated project is intentionally ignored by Git to keep the repository authorable from Windows and avoid pbxproj merge churn.

## Third-party dependency budget

Runtime dependencies are intentionally limited to:

1. YouTubeKit;
2. GoogleSignIn / GoogleSignInSwift.

XcodeGen is a development tool, not a shipped runtime dependency.

Any new runtime dependency requires an ADR explaining why native APIs or existing code are insufficient.
