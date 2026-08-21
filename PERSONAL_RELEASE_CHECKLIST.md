# PERSONAL_RELEASE_CHECKLIST — FocusTube

Everything that could be completed without physical access to the owner's
iPhone, Apple signing identity, or real Google credentials has been completed
and validated on the Apple CI build plane (see `.agent/STATE.yaml` and
`.agent/checkpoints/` for evidence). This list contains **only** the steps that
genuinely require the owner.

## 1. Apple signing & install (requires owner Apple ID / device)

- [ ] Open `FocusTube.xcodeproj` (regenerate first: `xcodegen generate`) in Xcode on a Mac.
- [ ] Select your Personal Team (or paid team) in the FocusTube target → Signing & Capabilities.
- [ ] Set a unique bundle id if `com.quantdale.FocusTube` conflicts with an existing App ID.
- [ ] Connect the iPhone, select it as the run destination, and install (Cmd+R or Product → Run).
- [ ] On the phone: Settings → General → VPN & Device Management → trust your developer certificate.

## 2. Google OAuth configuration (requires owner Google Cloud project)

- [ ] In Google Cloud Console, create/select an OAuth 2.0 Client ID of type iOS with bundle id matching the app.
- [ ] Add to `Config/Info.plist`: `GIDClientID` (the client id string) and a `CFBundleURLTypes` entry whose scheme is the **reversed client id**.
- [ ] If using a `GoogleService-Info.plist`, place it in `Config/` (gitignored) and reference it from the project.
- [ ] First launch → sign in with the real Google account and confirm subscriptions load.

No client ids, secrets, or tokens are committed; `Config/Secrets.local.xcconfig`
is the intended local override point and is gitignored.

## 3. Device-only verification (cannot be simulated faithfully)

- [ ] Background audio: lock the screen during playback; audio continues; lock-screen controls play/pause/seek.
- [ ] Bluetooth/headset controls route to the app.
- [ ] PiP: background the app during playback; picture-in-picture continues.
- [ ] Real interruption: take a phone call during playback → pause; end call → resume (if shouldResume).
- [ ] Genuine suspension download: start a download, background/suspend the app, confirm the transfer completes and appears in Downloads after relaunch.
- [ ] Wi-Fi ↔ cellular transition during a download and during playback.
- [ ] Delete a download on device; confirm file + metadata disappear and storage is reclaimed.

## 4. Known limitations to accept at release

- Live YouTube extraction depends on YouTubeKit 0.4.8 against current YouTube
  behavior; if extraction breaks upstream, diagnose before upgrading the pin.
- Real Google subscription/comment actions were implemented against the typed
  Data API client and covered by deterministic fakes; they have not been
  exercised against live Google servers (no credentials available to CI).
- Remaining Medium/Low debt is catalogued in `.agent/HARDENING_BACKLOG.md`.
