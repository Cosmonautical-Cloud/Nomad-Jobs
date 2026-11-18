# audiomuse-ai

Runs [AudioMuse-AI](https://github.com/) (native macOS `.app` bundle) —
audio analysis / smart-playlist generation against the library, backed by
its own `audiomuse` database on the shared [`postgres`](../postgres) cluster
and Redis DB index `2` on the shared [`redis`](../redis) primary (both
discovered via Consul service tags, not hardcoded hosts).

Pinned to `orion.cosmonautical.cloud`: the `.app` bundle
(`/Applications/AudioMuse-AI.app`) and its local state
(`~/Library/AudioMuse-AI`, including an embedded Postgres in `pgdata/` that
the app uses instead of the shared cluster despite the `POSTGRES_*` env) only
exist on that host. Moving it means copying both with the job stopped.

No Traefik tags — internal-only, not exposed outside the cluster. TCP health
check only, no HTTP endpoint check (the app doesn't expose one at the root).

## Consul KV keys

| Key | Used for |
|---|---|
| `audiomuse/DB_PASSWORD` | Postgres role password |
| `redis/PASSWORD` | Redis auth |

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
