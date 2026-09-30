# slskd

Runs [slskd](https://github.com/slskd/slskd) `0.24.1` (artifact-downloaded,
checksum-pinned) — a Soulseek client/daemon — ports `5030`/`5031`/`50300`
(the last being the actual Soulseek peer port, kept in sync with the UniFi
router's port-forward rule by the `update-port-forward` prestart task, same
pattern as `traefik`'s but for a single hardcoded rule ID rather than
several).

Persistence is layered: `slskd.yml` config and a few cache/db files sync
to/from `/Volumes/Cosmonautical/slskd/persistent` every 5 minutes (same
pattern as `sabnzbd`'s config), while `transfers.db` and `events.db`
specifically are continuously replicated via Litestream to the
`slskd-backups` bucket on [`seaweedfs-filer`](../seaweedfs-filer)'s S3
gateway and restored from there on start — same reasoning as `sabnzbd`'s
history DB: these two files change too often for a 5-minute snapshot to be
a good backup strategy.

The `ensure-backup-bucket` prestart task creates `slskd-backups` (via
`weed shell -filer=... s3.bucket.create`, idempotent) before Litestream
ever starts. This exists because Litestream doesn't create its own
destination bucket — found 2026-09-30 when this job's Terraform migration
re-registered it and replication silently failed for hours with
`NoSuchBucket` errors, since the bucket had genuinely never existed on
`seaweedfs-filer` before. See `CHANGELOG.md`.

No Traefik tags — internal-only.

## Consul KV keys

| Key | Used for |
|---|---|
| `seaweedfs-s3/ACCESS_KEY` | Litestream replication target credentials |
| `seaweedfs-s3/SECRET_KEY` | Litestream replication target credentials |
| `unifi/NOMAD_USER_PASSWORD` | UniFi controller login, for `update-port-forward`'s rule update |

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
