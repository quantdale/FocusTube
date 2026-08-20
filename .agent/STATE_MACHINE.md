# Autonomous Development State Machine

```text
READY
  -> WORKING(packet)
  -> LOCAL_VALIDATION
  -> REMOTE_APPLE_VALIDATION (when Apple-specific)
  -> REVIEW_EVIDENCE
      -> FIXING -> LOCAL_VALIDATION
      -> CHECKPOINT (if gate crossed)
      -> READY(next packet)

Any Critical/High regression -> BLOCKED_FIX_REQUIRED
External extractor outage -> BLOCKED_UPSTREAM only after evidence distinguishes it from app regression
```

## Rules

- A packet may not advance from validation merely because code compiles locally on Windows when the changed path is Apple-specific.
- Remote Apple validation is mandatory for Xcode project, SwiftUI, AVKit/AVFoundation, SwiftData, GoogleSignIn, or simulator behavior.
- Live YouTube extraction failure is investigated independently; deterministic app tests must remain runnable with a fake extractor.
- `BLOCKED_UPSTREAM` records evidence and avoids architectural panic changes such as adding an unauthorized fallback.
