# lidarr

Runs Lidarr `3.1.6.5078` (artifact-downloaded, checksum-pinned, ad-hoc
codesigned at deploy time via `codesign --sign - --force` since it's an
unsigned release binary), pinned to `betelgeuse.cosmonautical.cloud`, port
`8686`.

Config lives on local disk (`/Users/violet/lidarr-local/config`) for
performance, not NFS — a prestart task restores `config.xml` from
`/Volumes/Cosmonautical/lidarr/config` if local state is missing (fresh
host/redeploy), and a sidecar task backs up the SQLite DB (`sqlite3 .backup`,
safe on a live DB) and `config.xml` back to that same NFS path every 5
minutes. No Traefik tags — internal-only, part of the *arr stack alongside
[`radarr`](../radarr) and [`sonarr`](../sonarr).

## Consul KV keys

None — no `template`/`{{ key ... }}` references in this job's spec.

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
