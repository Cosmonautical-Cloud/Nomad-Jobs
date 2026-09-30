# audiomuse-ai

Runs [AudioMuse-AI](https://github.com/) (native macOS `.app` bundle) —
audio analysis / smart-playlist generation against the library, backed by
its own `audiomuse` database on the shared [`postgres`](../postgres) cluster
and Redis DB index `2` on the shared [`redis`](../redis) primary (both
discovered via Consul service tags, not hardcoded hosts).

No Traefik tags — internal-only, not exposed outside the cluster. TCP health
check only, no HTTP endpoint check (the app doesn't expose one at the root).

## Consul KV keys

| Key | Used for |
|---|---|
| `audiomuse/DB_PASSWORD` | Postgres role password |
| `redis/PASSWORD` | Redis auth |

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
