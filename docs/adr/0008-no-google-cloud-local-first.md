# ADR-0008 — No Google Cloud: link-based, local-first app with public feeds

**Status:** Accepted (2026-10-16, Michael's direction at 3:20 PM Manila). This ADR supersedes
the Data API and OAuth parts of ADR-0005 and the product spec (Google sign-in, Data API v3 feed,
search, comments, rating, subscribe and playlists). ADR-0007 still applies: playback uses the
official IFrame embed only.

## Context
Michael does not want a Google Cloud Console project, an OAuth client, an API key, or the
YouTube Data API v3. Paid services are not allowed. The app must stay within the YouTube ToS and
the App Store guidelines.

## Decision
1. **No sign-in and no API key.** GoogleSignIn, `YouTubeDataClient` and every Data API
   feature are removed: account feed, search, comments, like/rating, account subscribe, account
   playlists and playlist writes.
2. **Content enters by link.** The user pastes or shares a URL. The link parser accepts:
   - videos: `watch?v=`, `youtu.be/`, `/embed/`, `/live/`, and `m.`/`music.` hosts;
   - playlists: `list=` on `/playlist` or on a watch URL;
   - channels: `/channel/UC…`.

   It **rejects `/shorts/`** with a clear message. Only `youtube.com`, `youtu.be` and
   `youtube-nocookie.com` hosts are accepted, over https.
3. **Channels must be given as `/channel/UC…` (channel ID).** `@handle`, `/c/` and `/user/`
   URLs are recognised but **not resolved**. The app explains how to get the ID: on YouTube,
   open the channel → About/More → Share channel → **Copy channel ID**, or paste the `/channel/`
   URL. Rationale: there is no documented, keyless, ToS-clean way to resolve a handle. oEmbed has
   no channel ID, and scraping channel HTML is out. A small, documented convenience is allowed:
   a pasted bare `UC…` ID (24 chars) is accepted.
4. **Feeds come from public Atom feeds.** Channel uploads use
   `https://www.youtube.com/feeds/videos.xml?channel_id=UC…`, and playlists use `…?playlist_id=PL…`.
   These are public, keyless, no-cost endpoints that YouTube serves for feed readers. The
   aggregator fetches each subscription's feed (bounded concurrency, about 15 recent entries per
   feed), merges them, de-duplicates by video ID, and sorts newest first. Refresh is
   user-initiated or happens on foreground, with a minimum interval of 15 minutes per feed.
   There is no background polling.
5. **Metadata comes from oEmbed** (`https://www.youtube.com/oembed?url=…&format=json`). It provides
   the title, author name/URL, thumbnail, and the embed width/height. It does **not** give the
   duration, the description or the channel ID. The video page shows what oEmbed and the feed
   provide (title, channel, publish date, feed description), plus "Open in YouTube".
6. **Local-first library.** Subscriptions (channel ID, title, added date), saved playlists,
   watch history with resume position, and Watch Later are all stored on the device (SwiftData in
   the app; pure Codable models and policies in core). There is no sync. Export/import as a
   JSON file is a later nice-to-have.
7. **Search tab → "Add" tab.** Keyless search of YouTube is not available within the ToS: the
   Data API is excluded, and scraping results pages is forbidden. The tab becomes **Add**: a
   paste-a-link field (plus clipboard detection when the user taps "Paste") and **local search**,
   a case-insensitive title/channel match over already-known videos (feed cache, history,
   Watch Later, saved playlists). Justification: it keeps a discovery entry point without
   violating the ToS, and it fits FocusTube's intentional, low-distraction goal.
8. **Shorts firewall without durations.** The feed has no duration field. The rules are:
   - (a) feed entries whose `link` is `/shorts/` are dropped (YouTube currently uses that link
     form for Shorts in feeds);
   - (b) oEmbed metadata whose embed is portrait (`height > width`) is treated as a Short and
     blocked when that metadata is known;
   - (c) pasted `/shorts/` links are rejected;
   - (d) the 180 s duration rule still applies when a duration is known (for example from the
     player's `getDuration` after load, which blocks autoplay-next and hides the item from feeds
     afterwards).

   **Limits:** a Short whose feed link is `/watch?v=` and whose oEmbed was never fetched can slip
   into the feed until its metadata is seen. This is documented and accepted. We prefer it to
   scraping.
9. **Removed features.** Comments, likes, account subscribe/unsubscribe and remote
   playlists are gone; "Open in YouTube" covers them. Watch Later is local.

## Consequences
- Blockers M4 (OAuth client and secrets) and M5 (authenticated live smoke) disappear, along with
  B4, B5 and B9. `Secrets.local.xcconfig` is only needed for `DEVELOPMENT_TEAM` (local signing).
- Network surface: `www.youtube.com/feeds/videos.xml`, `www.youtube.com/oembed`, the IFrame
  embed (`youtube.com/iframe_api`, `youtube-nocookie.com`) and thumbnails (`i.ytimg.com`).
  Nothing else.
- Feed and oEmbed formats are unofficial-but-public. Parsers are tolerant: unknown elements are
  ignored, and a malformed entry is skipped and counted. They are covered by fixture tests.
- Everything in core (link parser, Atom parser, oEmbed decoding, library models, aggregator,
  Shorts rules) is Linux-tested. App wiring is verified only by macOS CI and on a device.

## Implementation plan (small PRs)
1. Core: `YouTubeLink` parser with tests.
2. Core: Atom feed parser and oEmbed client (HTTP behind a protocol) with fixture tests.
3. Core: local library models and policies (subscriptions, Watch Later, history/resume,
   saved playlists) and `PublicFeedAggregator` (Shorts firewall, de-dup, sort, refresh interval).
4. App: remove GoogleSignIn, `YouTubeDataClient`, auth/settings sign-in, comments, rating and
   the account actions. Wire local stores, the subscriptions feed, the Add tab and the video page
   over oEmbed. Update the UI-test fixtures.
5. Core cleanup: delete `YouTubeAPI`/`YouTubeDataClient`/`AccountActions`/`Comments`/`Search`.
