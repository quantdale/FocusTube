# DEVICE VALIDATION — OWNER BATCH A

FocusTube release validation (DEVICE_VALIDATION_V1). Everything automatable
has already been done by the agent: OAuth/signing plumbing is wired
(`Config/Secrets.local.xcconfig` is the only local file you create), CI is
green, deterministic tests pass. This page contains every remaining step that
physically requires you, consolidated into ONE session (~30–40 min).
Return the numbered results exactly as listed under "What to send back".

## Part 0 — One-time setup (before the batch)

1. **Apple signing** (needs Xcode on a Mac + your iPhone):
   - Either set `DEVELOPMENT_TEAM = <your 10-char Team ID>` in
     `Config/Secrets.local.xcconfig` (automatic signing picks it up), or select
     your team in Xcode → FocusTube target → Signing & Capabilities.
   - If bundle id `com.quantdale.FocusTube` conflicts with an existing App ID,
     also set `PRODUCT_BUNDLE_IDENTIFIER` accordingly there.
2. **Google Cloud Console** (same project as your OAuth client):
   - Create/select an OAuth 2.0 Client ID of type **iOS**, bundle id matching above.
   - Enable **YouTube Data API v3** for that project.
   - Fill in `Config/Secrets.local.xcconfig`:
     `GOOGLE_CLIENT_ID` (the client id string),
     `GOOGLE_REVERSED_CLIENT_ID` (the reversed client id).
3. Regenerate + open: `xcodegen generate` → `FocusTube.xcodeproj`.

## Batch A (one phone session)

| # | Action | Expected |
|---|--------|----------|
| A1 | Run (Cmd+R) on the iPhone | app installs + launches, four tabs |
| A2 | Home: tap "Sign in with Google", complete real account sign-in | Google sheet closes, subscription feed lists long-form videos |
| A3 | Inspect the feed; tap "Load more" once | no Shorts/vertical items ever; more videos appended (no auto-loading) |
| A4 | Search tab: type slowly WITHOUT pressing return | no network requests while typing |
| A5 | Submit a search for long-form content | results appear, again no Shorts |
| A6 | Open a video ≥ 10 min long | native player starts; title/channel correct |
| A7 | Open download quality picker on that video | only members of 1080/720/480/360 actually available (note WHICH) |
| A8 | Start the highest-quality download → immediately background app → lock screen → wait 5 min → unlock, reopen Downloads | transfer continued or resumed; progress advanced; no error |
| A9 | When download completes: enable Airplane Mode → play downloaded file → seek → pause/play → force-quit app → reopen → play again | offline playback works; resumes from stored position |
| A10 | Airplane Mode OFF → stream a video → background app → lock screen | audio continues; lock screen shows title/channel/progress |
| A11 | From lock screen / Control Center: pause, play | each press does exactly one action (no doubles) |
| A12 | Same playing video: enter PiP (swipe home), go to Home Screen, return | PiP keeps playing outside app; controls work; state coherent on return |
| A13 | If AirPods/Bluetooth/wired headset available: play/pause from headphones | same single-action behavior |
| A14 | Downloads tab: delete the downloaded file | row disappears; Settings → General → iPhone Storage shows space reclaimed |

## What to send back

For EACH item A1–A14: **pass / fail**, plus:
- fail → exact on-screen error text or a photo/screenshot;
- A2/A6/A10/A12 → a photo of the screen (phone camera is fine);
- your **iPhone model + iOS version**;
- anything that felt wrong even if it "worked".

Do not debug anything yourself — raw observations are enough; diagnosis and
fixes are handled on this side, followed by CI re-validation and (if needed)
a short Batch B re-test of only the affected items.
