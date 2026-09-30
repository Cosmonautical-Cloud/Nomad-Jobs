# nextcloud-cron

Periodic batch job (`*/5 * * * *`) that runs Nextcloud's own `cron.php`
background job runner — the standard way Nextcloud processes its internal
job queue (notifications, federation, housekeeping, etc.) outside of a web
request. Same `raw_exec` + Homebrew PHP setup, same pinned Nextcloud
version, and same Consul KV secrets (`nextcloud/DB_PASSWORD`,
`redis/PASSWORD`) as the main [`nextcloud`](../nextcloud) job — see that
job's README for the shared app details, and `.agents/AGENTS.md` for why
this job's schedule is staggered against its four siblings.

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
