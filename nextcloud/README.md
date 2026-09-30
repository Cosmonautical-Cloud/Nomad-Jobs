# nextcloud

The main Nextcloud service job: Caddy (reverse proxy + static file serving)
and PHP-FPM running side by side in one `raw_exec` task, serving
`drive.cosmonautical.cloud` on port 8083 behind Traefik. Backed by Postgres
and Redis (both discovered via Consul service tags), with app data on the
NAS's NFS export (`/Volumes/Cosmonautical/nextcloud/data`) and app
config/custom-apps on a separate persistent path
(`/Volumes/Cosmonautical/nextcloud/persistent`), synced back from local
ephemeral disk every 5 minutes.

Nextcloud version `34.0.4`, downloaded and checksum-verified via an
`artifact` block on every deploy. Caddy `2.11.4` (mac_arm64 build), same
pattern.

This job has four periodic siblings, each its own Nomad job/Terraform
resource/directory (see the repo README's "Why five directories for one
app"):

| Job | Schedule (UTC) | What it does |
|---|---|---|
| [`nextcloud-cron`](../nextcloud-cron) | `*/5 * * * *` | Runs Nextcloud's own `cron.php` background jobs |
| [`nextcloud-preview-generate`](../nextcloud-preview-generate) | `*/15 * * * *` | Pre-generates file previews/thumbnails |
| [`nextcloud-roms-scan`](../nextcloud-roms-scan) | `0 0 * * *` | Rescans the external `/ROMs` mount into Nextcloud's file index |
| [`nextcloud-s3-backup`](../nextcloud-s3-backup) | `0 3 * * *` | Backs up Nextcloud's data directory to B2-compatible S3 |

All five share the same `nextcloud/DB_PASSWORD` and `redis/PASSWORD` Consul
KV secrets, and all pin the same Nextcloud release for consistency across
the app's own code and its CLI (`occ`) tooling — see
`.agents/AGENTS.md` for the full Consul KV convention.

## Consul KV keys

| Key | Used for |
|---|---|
| `nextcloud/ADMIN_PASSWORD` | Initial admin account password (`occ maintenance:install`) |
| `nextcloud/DB_PASSWORD` | Postgres role password |
| `redis/PASSWORD` | Redis auth |
| `smtp/SERVER` | Outbound mail host |
| `smtp/PORT` | Outbound mail port |
| `smtp/USERNAME` | Outbound mail username |
| `smtp/PASSWORD` | Outbound mail password |

For history/rationale (config decisions, incidents, fixes), see
[`CHANGELOG.md`](../CHANGELOG.md).
