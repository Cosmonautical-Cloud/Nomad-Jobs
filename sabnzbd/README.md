# sabnzbd

Runs SABnzbd (native macOS `.app` bundle), port `8085`, sticky ephemeral
disk. Config (`sabnzbd.ini`) syncs to/from
`/Volumes/Cosmonautical/sabnzbd/persistent` every 5 minutes, same
restore-on-start pattern as `lidarr`'s config.

Its history database (`admin/history1.db`) is continuously replicated via
[Litestream](https://litestream.io/) to the `sabnzbd-backups` bucket on
[`seaweedfs-filer`](../seaweedfs)'s S3 gateway, and restored from
there on start if missing locally — same pattern as [`slskd`](../slskd)'s
`transfers.db`/`events.db`. This is a different, lighter-weight persistence
strategy than `lidarr`'s periodic `sqlite3 .backup` copy: continuous
streaming replication vs. a snapshot every 5 minutes.

The `ensure-backup-bucket` prestart task creates `sabnzbd-backups` (via
`weed shell -filer=... s3.bucket.create`, idempotent) before Litestream
ever starts. This exists because Litestream doesn't create its own
destination bucket — found 2026-09-30 when this job's Terraform migration
re-registered it and replication silently failed for hours with
`NoSuchBucket` errors, since the bucket had genuinely never existed on
`seaweedfs-filer` before. See `CHANGELOG.md`.

## Consul KV keys

| Key | Used for |
|---|---|
| `seaweedfs-s3/ACCESS_KEY` | Litestream replication target credentials |
| `seaweedfs-s3/SECRET_KEY` | Litestream replication target credentials |

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
