# 04 — Google Authentication and YouTube Data API

## Authentication

Use GoogleSignIn / GoogleSignInSwift from the official GoogleSignIn-iOS package. Do not implement raw password authentication or embed Google login in WKWebView.

Configuration belongs in local secrets/configuration, not source control.

Do not give CI or coding agents a real user's password, 2FA secret, or browser cookies. Deterministic UI tests use a fake `AuthenticationProviding` implementation.

## Scope strategy

Request the minimum scopes necessary. `youtube.force-ssl` is required by comment insertion and supports several authenticated account actions. Scope expansion should be incremental and tied to a feature requirement.

## API client

Use a typed direct REST client implemented with URLSession + Codable. Avoid a large generic Google API wrapper.

Expected methods include:

- subscriptions list/insert/delete;
- channels/videos/playlistItems list;
- search list;
- commentThreads list/insert;
- comments list/insert;
- videos rate/getRating if used;
- playlists/playlistItems operations when supported and useful.

## Current quota model

As verified from Google documentation on 2026-08-20:

- `search.list` has its own default bucket of 100 calls/day and each call costs 1 search quota unit;
- `videos.insert` has a separate bucket not relevant to FocusTube;
- most other endpoints share a default 10,000-unit/day bucket;
- common reads such as subscriptions.list, playlistItems.list, videos.list, comments.list cost 1 unit;
- many write operations cost 50 units.

Therefore Search must **not** fire on every keystroke. The first version uses explicit submit.

## Subscription feed strategy

Build Home from deliberate subscription data instead of attempting to recreate YouTube's private recommendation feed:

1. retrieve authenticated subscriptions;
2. identify channel uploads sources;
3. fetch recent uploads efficiently;
4. hydrate metadata/durations in batches where possible;
5. apply ShortFormPolicy before display;
6. merge/sort by publish time;
7. cache the resulting feed locally;
8. refresh explicitly or after a reasonable staleness threshold.

## Comments

- `commentThreads.list` retrieves top-level threads;
- not every reply is necessarily embedded in a thread response, so use `comments.list` when full replies are needed;
- `commentThreads.insert` creates a top-level comment;
- `comments.insert` creates a reply.

The UI must handle comments-disabled videos as a normal state.

## Watch Later / history limitation

Do not architect FocusTube around guaranteed official Watch Later/Watch History access. Maintain local FocusTube history, resume progress, and local save semantics. Treat supported YouTube playlists as a separate synchronization feature.
