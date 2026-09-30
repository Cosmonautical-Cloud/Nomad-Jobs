# sabnzbd

Runs SABnzbd (native macOS `.app` bundle), port `8085`, sticky ephemeral
disk. Config (`sabnzbd.ini`) syncs to/from
`/Volumes/Cosmonautical/sabnzbd/persistent` every 5 minutes, same
restore-on-start pattern as `lidarr`'s config.

Its history database (`admin/history1.db`) is continuously replicated via
[Litestream](https://litestream.io/) to the `sabnzbd-backups` bucket on
[`seaweedfs-filer`](../seaweedfs-filer)'s S3 gateway, and restored from
there on start if missing locally — same pattern as [`slskd`](../slskd)'s
`transfers.db`/`events.db`. This is a different, lighter-weight persistence
strategy than `lidarr`'s periodic `sqlite3 .backup` copy: continuous
streaming replication vs. a snapshot every 5 minutes.

## Consul KV keys

| Key | Used for |
|---|---|
| `seaweedfs-s3/ACCESS_KEY` | Litestream replication target credentials |
| `seaweedfs-s3/SECRET_KEY` | Litestream replication target credentials |

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
