# nextcloud-roms-scan

Periodic batch job (`0 0 * * *`) that rescans the externally-mounted `/ROMs`
share into Nextcloud's file index (`occ files:scan --path="admin/files/ROMs"`),
so files added outside of Nextcloud's own upload flow show up without
waiting for a lazy on-access scan.

Has a `wait-for-mounts` prestart task that blocks (up to 60s, polling every
2s) until both `/Volumes/Cosmonautical` and `/Volumes/ROMs` are actually
mounted, and until Nextcloud's own `config.php` exists — guards against a
reboot race where this job's cron fires before the NFS mounts or the main
`nextcloud` job's first-run setup have finished.

Same `raw_exec` + Homebrew PHP setup, same pinned Nextcloud version, and
same Consul KV secrets (`nextcloud/DB_PASSWORD`, `redis/PASSWORD`) as the
main [`nextcloud`](../nextcloud) job — see that job's README for the shared
app details, and `.agents/AGENTS.md` for why this job's schedule is
staggered against its siblings.

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
