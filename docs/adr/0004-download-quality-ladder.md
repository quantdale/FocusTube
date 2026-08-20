# ADR-0004 — Fixed Download Quality Ladder

**Status:** Accepted

## Decision

Only 1080p, 720p, 480p, and 360p are user-visible download qualities. 1080p is the hard maximum.

## Rules

- Higher resolutions are discarded.
- Missing exact resolutions are omitted, not transcoded into existence.
- Default selection is the highest available allowed resolution.
