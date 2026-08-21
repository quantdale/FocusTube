# ADR-0006 — Per-Quality Media Storage Layout

**Status:** Accepted

## Context

docs/03 originally sketched a single-file layout, `Media/<video-id>/media.<container>`,
with one final file per video. The implemented download system keys every
transfer by `<videoID>-<quality>` and supports holding several exact qualities
of the same video at once (each quality is independently planned, downloaded,
validated, and deletable). A single file per video cannot represent that state:
a second quality would overwrite the first, and delete/reconcile could not
distinguish which quality a file belongs to.

## Decision

Final media is stored per quality:

```text
Application Support/
  FocusTube/
    Media/
      <videoID>/
        <quality>/
          media.<container>
```

## Consequences

- Multiple exact qualities of one video coexist without collision; each is
  registered, played, resumed, and deleted independently.
- Delete/reconcile operates on `<videoID>/<quality>` directories, so a missing
  or corrupted single-quality file never invalidates its siblings.
- The deviation from the docs/03 sketch is layout-only: storage remains
  filesystem-under-Application-Support with SwiftData metadata, exactly as
  locked. Temporary/component files stay in `FocusTube/Incomplete` until
  finalization.
- docs/03's layout section describes the conceptual single-file case; this ADR
  is authoritative for the multi-quality reality.
