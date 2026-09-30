# nextcloud-s3-backup

Periodic batch job (`0 3 * * *`) that backs up Nextcloud's data directory
(`/Volumes/Cosmonautical/nextcloud/data`) to a B2-compatible S3 bucket
(`cosmonautical-nextcloud-backups`) via `rclone` (`v1.75.1`, checksum-pinned,
downloaded fresh each run), timestamped per run
(`b2:cosmonautical-nextcloud-backups/<UTC timestamp>`). Prunes backups older
than 7 days after a successful copy — a failed copy leaves existing backups
untouched rather than pruning first.

Uses its own Consul KV secrets under `s3/` (`s3/KEY_ID`,
`s3/APPLICATION_KEY`, `s3/ENDPOINT`) rather than the `nextcloud/*` /
`redis/*` keys the other four nextcloud jobs share, since it talks to S3
directly and never touches Postgres/Redis.

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
