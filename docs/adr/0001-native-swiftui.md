# ADR-0001 — Native SwiftUI iOS Application

**Status:** Accepted

## Decision

Build FocusTube as a native SwiftUI iOS app rather than React Native/Expo or a YouTube WebView wrapper.

## Rationale

The project's highest-value capabilities are native playback, PiP/background audio, background URLSession downloads, filesystem persistence, AVFoundation muxing, and an Apple-native extractor. A cross-platform abstraction would add maintenance without solving the Windows build constraint. Remote macOS CI solves that constraint more directly.
