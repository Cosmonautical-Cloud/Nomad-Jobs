# nextcloud

The Nextcloud stack: one long-running service job plus four periodic batch
jobs, each its own Nomad job and Terraform resource, with all five specs
kept side by side in this folder (see the repo README's "Stack
folders").

| Job | Spec | Schedule (UTC) | What it does |
|---|---|---|---|
| `nextcloud` | [`nextcloud.nomad.hcl`](nextcloud.nomad.hcl) | service | Caddy + PHP-FPM serving `drive.cosmonautical.cloud` |
| `nextcloud-cron` | [`nextcloud-cron.nomad.hcl`](nextcloud-cron.nomad.hcl) | `*/5 * * * *` | Runs Nextcloud's own `cron.php` background jobs |
| `nextcloud-preview-generate` | [`nextcloud-preview-generate.nomad.hcl`](nextcloud-preview-generate.nomad.hcl) | `*/15 * * * *` | Pre-generates file previews/thumbnails |
| `nextcloud-roms-scan` | [`nextcloud-roms-scan.nomad.hcl`](nextcloud-roms-scan.nomad.hcl) | `0 0 * * *` | Rescans the external `/ROMs` mount into Nextcloud's file index |
| `nextcloud-s3-backup` | [`nextcloud-s3-backup.nomad.hcl`](nextcloud-s3-backup.nomad.hcl) | `0 3 * * *` | Backs up Nextcloud's data directory to B2-compatible S3 |

The four periodic jobs' schedules are staggered against each other and the
main service's load — see `.agents/AGENTS.md` for why.

## nextcloud

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

`nextcloud`, `nextcloud-cron`, `nextcloud-preview-generate`, and
`nextcloud-roms-scan` all use the same `raw_exec` + Homebrew PHP setup, pin
the same Nextcloud release (for consistency across the app's own code and
its CLI (`occ`) tooling), and share the same `nextcloud/DB_PASSWORD` and
`redis/PASSWORD` Consul KV secrets — see `.agents/AGENTS.md` for the full
Consul KV convention.

## nextcloud-cron

Runs Nextcloud's own `cron.php` background job runner — the standard way
Nextcloud processes its internal job queue (notifications, federation,
housekeeping, etc.) outside of a web request.

## nextcloud-preview-generate

Runs `occ preview:pre-generate` to pre-render file previews/thumbnails ahead
of time, rather than generating them on-demand on first view.

## nextcloud-roms-scan

Rescans the externally-mounted `/ROMs` share into Nextcloud's file index
(`occ files:scan --path="admin/files/ROMs"`), so files added outside of
Nextcloud's own upload flow show up without waiting for a lazy on-access
scan.

Has a `wait-for-mounts` prestart task that blocks (up to 60s, polling every
2s) until both `/Volumes/Cosmonautical` and `/Volumes/ROMs` are actually
mounted, and until Nextcloud's own `config.php` exists — guards against a
reboot race where this job's cron fires before the NFS mounts or the main
`nextcloud` job's first-run setup have finished.

## nextcloud-s3-backup

Backs up Nextcloud's data directory (`/Volumes/Cosmonautical/nextcloud/data`)
to a B2-compatible S3 bucket (`cosmonautical-nextcloud-backups`) via
`rclone` (`v1.75.1`, checksum-pinned, downloaded fresh each run),
timestamped per run (`b2:cosmonautical-nextcloud-backups/<UTC timestamp>`).
Prunes backups older than 7 days after a successful copy — a failed copy
leaves existing backups untouched rather than pruning first.

Uses its own Consul KV secrets under `s3/` rather than the `nextcloud/*` /
`redis/*` keys the other four jobs share, since it talks to S3 directly and
never touches Postgres/Redis.

## Consul KV keys

| Key | Used by | Used for |
|---|---|---|
| `nextcloud/ADMIN_PASSWORD` | `nextcloud` | Initial admin account password (`occ maintenance:install`) |
| `nextcloud/DB_PASSWORD` | all but `nextcloud-s3-backup` | Postgres role password |
| `redis/PASSWORD` | all but `nextcloud-s3-backup` | Redis auth |
| `smtp/SERVER` | `nextcloud` | Outbound mail host |
| `smtp/PORT` | `nextcloud` | Outbound mail port |
| `smtp/USERNAME` | `nextcloud` | Outbound mail username |
| `smtp/PASSWORD` | `nextcloud` | Outbound mail password |
| `s3/KEY_ID` | `nextcloud-s3-backup` | B2-compatible S3 access key ID |
| `s3/APPLICATION_KEY` | `nextcloud-s3-backup` | B2-compatible S3 secret key |
| `s3/ENDPOINT` | `nextcloud-s3-backup` | B2-compatible S3 endpoint URL |

For history/rationale (config decisions, incidents, fixes), see
[`CHANGELOG.md`](../CHANGELOG.md).
