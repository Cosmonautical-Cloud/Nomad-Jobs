# dispatcharr

Runs [Dispatcharr](https://github.com/Dispatcharr/Dispatcharr)
(`ghcr.io/dispatcharr/dispatcharr:0.34.1-arm64`, container driver) — IPTV/EPG
management — as two tasks: `dispatcharr` (the web server, pinned to
`orion.cosmonautical.cloud`, port `9191`) and `celery` (background
worker, same image, `entrypoint.celery.sh`, 1–2 workers).

Backed by its own database/role on the shared [`postgres`](../postgres)
cluster and DB index on [`redis`](../redis). **Points at `postgres.service.consul`
/ `redis.service.consul` directly as static env vars**, rather than the
`{{ range service "..." }}{{ .Address }}{{ end }}` template pattern most
other jobs here use — functionally equivalent (both resolve through Consul
DNS to the current leader/master), just a different mechanism; worth knowing
if `postgres`'s or `redis`'s Consul service naming ever changes.

Local hot-path data on internal disk (`/Users/violet/dispatcharr-local/data`),
with NFS-backed volumes for backups/recordings/uploads/plugins.

`/Volumes/Cosmonautical/dispatcharr-vod` is mounted at `/VODS` in both
tasks. The VOD to Media Library plugin writes `.strm` files there
(`/VODS/Movies`, `/VODS/Series`, its defaults), and Jellyfin on cassiopeia
reads them from the same NFS path.

## Consul KV keys

| Key | Used for |
|---|---|
| `dispatcharr/DB_PASSWORD` | Postgres role password |
| `redis/PASSWORD` | Redis auth |

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
