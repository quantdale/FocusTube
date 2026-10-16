# DECISIONS — Phase 1 Assessment

## Locked decisions found (source: README, START_HERE, docs/adr/0001–0006)
- Native SwiftUI, iOS 17+, Swift 6; no WebView (ADR-0001).
- YouTubeKit is the only extractor, local only; no yt-dlp or remote extractor (ADR-0002).
- XcodeGen generates the project; `.xcodeproj` is not committed (ADR-0003).
- The download ladder is exactly 1080/720/480/360; no transcoding to fill gaps (ADR-0004).
- No backend in V1 (ADR-0005).
- Per-quality media layout `Media/<id>/<quality>/` (ADR-0006).
- Runtime dependencies are limited to YouTubeKit and GoogleSignIn.
- Shorts are hard-blocked, with a conservative 180 s cutoff.

## Decisions made in this assessment
- D1: The assessment is docs only, on local branch `docs/phase1-assessment`.
  No push, no PR, no code changes.
- D2: The CI failure is classified as a test-determinism defect (P0), not a
  product regression. Basis: the hydration result is index-keyed
  (`YouTubeAPI.swift`), and the test asserts the order of recorded requests.
- D3: I did not reopen any locked decision. None of the evidence gathered
  requires an ADR.
- D4: "Feature-complete" is defined as spec jobs on device + green and
  non-flaky CI (see ROADMAP.md), not just CI green.

## 2026-10-16 — CI actions moved to Node 24 majors
Moved `actions/checkout` from v4 to v7, `actions/cache` from v4 to v6, and `actions/upload-artifact`
from v4 to v7. The v4 majors target Node 20, which is deprecated, and the runner forces them onto Node 24.
None of the inputs we use changed. The `aws/tap` untrusted-tap warning did not appear
in the 2026-10-15 iOS CI run (38761375821), so this change makes no Homebrew change.
## 2026-10-16 — Blockers never stop work
This is the standing rule recorded in `AGENTS.md`. Log the blocker in the BLOCKERS morning queue, work around it safely, merge only when CI is green, and continue.
## 2026-10-16 — `aws/tap` warning and the `AppDependencies` fatalError
- `aws/tap`: the warning did not appear in the iOS CI logs for runs 38761375821 and 38797704060, so no change was made. Reopen only if the warning comes back.
- `AppDependencies.production()` keeps its `fatalError`, which runs only if the *in-memory* `ModelContainer` also fails. To replace it, the app would need a degraded launch UI with no SwiftData. That path cannot be exercised on CI or Linux; it needs runtime proof on a device. Under the merge rule we do not merge it until device validation is possible. The item is deferred, not dropped.

## 2026-10-16 — Agent-adapter dirs are kept, not consolidated (closes P4)
`.agents/skills/goal/SKILL.md`, `.claude/commands/goal.md`, `.opencode/commands/goal.md`
and `.kimi-code/AGENTS.md` are tiny `/goal` shims. Each tool finds them only at its own
fixed path, so they can't be merged into one directory without breaking discovery
(symlinks are unreliable on the Windows authoring host). All four already defer to the
one canonical source: root `AGENTS.md` plus `.agent/` (the fifth dir). Rule: change the
behavior in `.agent/`; edit a shim only if its pointer text changes.

## 2026-10-16 — ADR-0007: official IFrame player; offline downloads removed (compliance)
Full text: [`docs/adr/0007-official-iframe-player.md`](adr/0007-official-iframe-player.md).
Supersedes ADR-0002, ADR-0004 and ADR-0006.
- Playback moves from YouTubeKit stream extraction + AVPlayer to the official YouTube
  IFrame Player API in a `WKWebView` (youtube-nocookie host, `playsinline=1`,
  `enablejsapi=1`). Reason: extraction and downloading violate the YouTube API ToS and
  App Store guideline 5.2.3; Michael's hard limit is ToS/App Store compliance.
- Core gets a platform-independent `PlayerEngine` protocol plus an IFrame command/bridge/state
  machine (Linux-tested). WebKit stays in the iOS target behind the protocol.
- **Offline downloads are removed, not kept.** There is no compliant way to download.
  For the transition only, download UI is compiled out behind `FOCUSTUBE_LEGACY_DOWNLOADS`
  (off by default, never set for shipped builds) so the deletion can land in small,
  CI-verified PRs; phase 3 deletes the code and the flag.
- Accepted losses: background audio (dropped), our PiP and lock-screen/remote-command
  integration (unsupported until a device shows WebKit behavior), the Downloads tab and the
  quality picker.
- Migration: 1a docs, 1b core, 2 iOS engine + switch-over, 3 deletions + YouTubeKit removal,
  4 device validation. See the ADR table.

## 2026-10-16 — ADR-0008: no Google Cloud; link-based, local-first app
Full text: [`docs/adr/0008-no-google-cloud-local-first.md`](adr/0008-no-google-cloud-local-first.md).
- No sign-in, no API key, no Data API v3. GoogleSignIn and the Data API client are removed.
- Content enters by pasted link. A link parser accepts videos, playlists and `/channel/UC…`
  channels, and rejects `/shorts/`.
- `@handle`, `/c/` and `/user/` are **not resolved**. The user is told to use "Share channel →
  Copy channel ID". Nothing is scraped.
- Feeds come from public Atom (`feeds/videos.xml?channel_id=` / `?playlist_id=`), and metadata from oEmbed.
- Subscriptions, Watch Later, history/resume and saved playlists are all local.
- The Search tab is replaced by an **Add** tab (paste a link, plus local search over known videos),
  because keyless YouTube search isn't possible within the ToS.
- Shorts: drop `/shorts/` feed links and portrait oEmbed embeds, reject pasted `/shorts/` links, and
  keep the 180 s rule when a duration is known. Documented leak: a Short with a `watch?v=` feed link
  can slip in until its metadata is seen.
- M4, M5, B4, B5 and B9 are dropped.

## 2026-10-17 — No Codex PR reviews
Michael's standing rule: never use Codex PR reviews (no `@codex` comments, no review requests, no waiting on Codex). On 2026-10-17 a repo grep found no Codex config. Disable any that appears. Merges are gated on CI checks only.
