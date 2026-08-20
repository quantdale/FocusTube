# Work Packet Index

`.agent/STATE.yaml` names the active packet. `.agent/WAYPOINTS.yaml` is the machine-readable dependency/status plan.

## Active campaign — IMPLEMENTATION_V1

Execute continuously in this dependency order unless state records a justified dependency-safe deviation:

1. `WP-000-BOOTSTRAP.md` — reproducible project + remote simulator CI. Gate G0.
2. `WP-001-EXTRACTION.md` — YouTubeKit local extraction adapter. G1.
3. `WP-002-PLAYBACK.md` — native online playback viability. G1.
4. `WP-003-COMBINED-DOWNLOAD.md` — background combined-stream download/offline playback. G1.
5. `WP-004-ADAPTIVE-1080.md` — separate 1080p video/audio + native mux proof. G1.
6. `WP-005-DURABLE-DOWNLOAD-MANAGER.md` — persistence, relaunch, retries, reconciliation. G2.
7. `WP-006-AUTH-DATA-API.md` — GoogleSignIn boundary + typed YouTube API client. G3.
8. `WP-007-HOME-SHORTS-FIREWALL.md` — subscription feed + hard focus filtering. G4.
9. `WP-008-SEARCH.md` — quota-aware explicit-submit search. G5.
10. `WP-009-VIDEO-COMMENTS-ACTIONS.md` — video page, comments, supported account actions. G6.
11. `WP-010-LIBRARY.md` — history/resume/offline management. G7.
12. `WP-011-BACKGROUND-MEDIA.md` — PiP/audio/Now Playing/remote-command implementation. G8.
13. Run `IC-EXIT` in `docs/14-ACCEPTANCE-GATES.md` and set `implementation_complete_ready_for_hardening`.

**Do not stop after a packet passes.** Checkpoint, advance state, and continue to the next ready packet.

## Out of current campaign

`WP-012-HARDEN-RELEASE.md` belongs to the later hardening/release campaign. Do not execute it merely because WP-011 finishes. The implementation campaign ends at `IC-EXIT`.

## Blocked packet behavior

When a packet is partially blocked:

- continue unblocked acceptance criteria inside it;
- if safe, continue dependency-independent roadmap work;
- record the precise blocked criterion/evidence in state;
- do not pretend a blocked gate passed;
- escalate only when no useful safe work remains.

## New packet rule

Create a new packet only when unplanned work is large enough to need an independent acceptance boundary. Small discoveries stay inside the active packet or hardening backlog. Use `TEMPLATE.md`.