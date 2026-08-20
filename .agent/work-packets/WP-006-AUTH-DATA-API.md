# WP-006-AUTH-DATA-API

**Milestone/Gate:** M3 / G3

## Objective

Add account-aware YouTube operations safely.

## Required work

- Configure GoogleSignIn using local secrets.
- Create AuthenticationProviding and fake test implementation.
- Implement typed YouTubeAPIClient with URLSession/Codable.
- Implement subscriptions list first.
- Map auth/quota/API errors.
- Add no-secret logging tests/review.

## Acceptance

- Real dev sign-in works at least once.
- CI tests do not require real credentials.
- Subscription list renders fixture and live integration state.

## Rules

- Preserve all locked decisions in `START_HERE.md` and `AGENTS.md`.
- Add/update deterministic tests with behavior changes.
- Record exact validation evidence in `.agent/STATE.yaml`.
- Do not advance the packet merely on code inspection.
