# 06 — Persistence and Data Model

## Storage split

Use SwiftData for metadata/index state and FileManager-backed directories for actual media files.

Do not put large video/audio blobs in SwiftData.

## Core persisted entities

### VideoRecord

- videoID (unique business key)
- title
- channelID/channelName
- publishedAt
- durationSeconds
- thumbnail references
- lastMetadataRefresh

### DownloadRecord

- stable local UUID
- videoID
- requestedQuality (360/480/720/1080)
- actualQuality
- state
- bytes received/expected where known
- local relative path
- component temp paths when active
- retry count
- created/started/completed timestamps
- typed last failure

### PlaybackProgress

- videoID
- positionSeconds
- durationSeconds
- updatedAt
- completion marker if desired

### WatchHistoryRecord

- videoID
- firstWatchedAt
- lastWatchedAt
- play count / last position reference

### AppSettings

- autoplay next default false
- related content default hidden
- cellular downloads default false
- preferred download quality default 1080p fallback-highest
- feed page size

## Migration policy

Every schema change after data exists requires an explicit migration plan and test fixtures. Never destroy the user's offline library simply because a schema changed.

## Reconciliation

At launch, periodically reconcile SwiftData download records against the filesystem:

- record says completed but file missing -> mark repair-needed/missing;
- file exists but no record -> quarantine/orphan record for safe cleanup, never silently delete immediately;
- temp files older than a safety threshold -> cleanup candidate after ensuring no URLSession task owns them.
