# postgres

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

Paired with [`postgres-backup`](../postgres-backup) for periodic dumps. For
history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
