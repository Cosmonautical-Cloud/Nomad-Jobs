# postgres

The shared Postgres stack: the Patroni-managed cluster itself plus a
periodic backup job, each its own Nomad job and Terraform resource, with
both specs kept side by side in this folder (see the repo README's "Stack
folders").

| Job | Spec | Schedule (UTC) | What it does |
|---|---|---|---|
| `postgres` | [`postgres.nomad.hcl`](postgres.nomad.hcl) | service | 3-node Patroni-managed Postgres cluster |
| `postgres-backup` | [`postgres-backup.nomad.hcl`](postgres-backup.nomad.hcl) | `0 */6 * * *` | `pg_dumpall` of the whole cluster to the NAS |

## postgres

A 3-node Postgres cluster (`postgresql@18` via Homebrew) managed by
[Patroni](https://patroni.readthedocs.io/) for automated leader election and
failover, one `patroni` group instance per host (`distinct_hosts = true`).
Each node runs Patroni against a local Consul-backed DCS (`consul: {host:
127.0.0.1:8500}`) for cluster coordination — no separate etcd/ZooKeeper.

Data directory (`/Users/violet/postgres-local/data`) is **local disk, not
NFS** — Patroni's own streaming replication handles copying data between
nodes, so there's no need for (and no benefit from, only latency risk in) a
shared NFS-backed data directory here. Contrast with `nextcloud`'s data path,
which *is* NFS-backed because Nextcloud itself has no built-in replication.

Two Consul services are registered per node:

- **`postgres`** — only healthy on the current leader (gated by Patroni's
  own `/primary` REST endpoint). This is the one Traefik routes to (TCP
  passthrough on `:15432`, see [`traefik`](../traefik)) and the one other
  jobs' `template` blocks should reference via `{{ range service "postgres"
  }}` — it always resolves to the current writer, even across a failover.
- **`postgres-node`** — healthy on every node regardless of role, gated by
  Patroni's general `/health` endpoint. Only useful for cluster-wide health
  monitoring, not for anything that needs to find the writer.

Why Patroni and not a simpler single-instance Postgres: this cluster backs
real stateful apps (`nextcloud`, `open-webui`) directly on `raw_exec`
macOS hosts with no shared block storage underneath Postgres itself —
automated failover here is what keeps those apps up through a host reboot or
failure, at the cost of the added Patroni/DCS complexity.

## postgres-backup

Runs `pg_dumpall` against the current Postgres leader (discovered via the
`postgres` Consul service, so it always finds the writer even after a
failover) and writes a gzip-compressed, timestamped dump to
`/Volumes/Cosmonautical/postgres-backups`. Prunes dumps older than 14 days,
but only after a successful dump — a failed `pg_dumpall` leaves existing
backups untouched rather than pruning first.

Waits (polling every 10s, up to 60 attempts) for `pg_isready` against the
discovered host before dumping, since the leader can briefly be unavailable
during a Patroni failover.

Backs up the whole cluster (`pg_dumpall`, not a per-database `pg_dump`) since
every app sharing the cluster (`nextcloud`, `open-webui`, more to come) needs
to be restorable together.

## Consul KV keys

| Key | Used by | Used for |
|---|---|---|
| `postgres/PATRONI_API_PASSWORD` | `postgres` | Patroni's own REST API basic auth |
| `postgres/PATRONI_SUPERUSER_PASSWORD` | `postgres`, `postgres-backup` | Postgres superuser (`violet`) + `pg_rewind` auth; `pg_dumpall` auth against the leader |
| `postgres/REPLICATOR_PASSWORD` | `postgres` | Streaming replication user |

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
