# nextcloud-preview-generate

Periodic batch job (`*/15 * * * *`) that runs Nextcloud's
`occ preview:pre-generate` to pre-render file previews/thumbnails ahead of
time, rather than generating them on-demand on first view. Same `raw_exec` +
Homebrew PHP setup, same pinned Nextcloud version, and same Consul KV
secrets (`nextcloud/DB_PASSWORD`, `redis/PASSWORD`) as the main
[`nextcloud`](../nextcloud) job — see that job's README for the shared app
details, and `.agents/AGENTS.md` for why this job's schedule is staggered
against its four siblings.

## Consul KV keys

| Key | Used for |
|---|---|
| `nextcloud/DB_PASSWORD` | Postgres role password |
| `redis/PASSWORD` | Redis auth |

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
