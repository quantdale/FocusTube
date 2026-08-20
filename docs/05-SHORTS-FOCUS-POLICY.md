# 05 — Shorts / Focus Policy

## Objective

Prevent FocusTube from becoming another short-form infinite-consumption surface.

## Hard invariants

- No Shorts tab.
- No Shorts carousel/shelf.
- No `/shorts/` route.
- No vertical swipe-to-next player.
- No implicit next-video autoplay by default.
- No infinite feed auto-pagination by default.
- Search/Home hide duration <= 180 seconds.
- A blocked item is not playable through an in-context override.

## Why duration <= 180 seconds

YouTube's current Shorts rules can include square/vertical videos up to three minutes. The public Data API does not expose a reliable universal `isShort` boolean. FocusTube therefore uses a conservative duration firewall for discovery surfaces.

This produces acceptable false positives. A two-minute long-form-style video may be hidden; that is preferable to leaking short-form content into the app.

## Boundary architecture

One domain service/policy owns the decision. Do not duplicate hard-coded `<= 180` checks across views.

Inputs may include:

- URL path;
- known duration;
- future metadata signals if stable and documented.

Outputs should be a typed result such as allowed / blocked(reason).

## External links

When the app receives a YouTube URL:

1. parse video ID/path;
2. immediately block explicit `/shorts/` paths;
3. fetch metadata when needed;
4. block duration <= 180 seconds;
5. only then enter normal video detail/playback.

## Regression tests

At minimum test:

- 179s blocked;
- 180s blocked;
- 181s allowed;
- `/shorts/<id>` blocked regardless of unknown duration;
- normal `/watch` long video allowed;
- Home feed removes blocked entries;
- Search results remove blocked entries;
- no UI test can navigate from a playing video to another by vertical swipe.
