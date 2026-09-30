# seerr

Runs Seerr (`ghcr.io/seerr-team/seerr:v3.4.1`, container driver) — media
request management (Overseerr-family) — routed at `seerr.jellify.app` (see
[`jellyfin`](../jellyfin)'s README for why). Backed by its own
database/role on the shared [`postgres`](../postgres) cluster. Config
volume on NFS (`/Volumes/Cosmonautical/seerr/config`).

## Consul KV keys

| Key | Used for |
|---|---|
| `seerr/DB_PASSWORD` | Postgres role password |

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
