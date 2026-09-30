# redis

A Redis Sentinel deployment for HA caching/key-value storage, three groups:

- **`primary`** (count 1, pinned to `taurus.cosmonautical.cloud`) — the
  writable node.
- **`replica`** (count 2, `distinct_hosts` + explicitly excluded from
  `taurus`) — read replicas on the other two hosts, replicating from the
  primary by hostname (`replicaof taurus.cosmonautical.cloud 6379`).
- **`sentinel`** (count 3, `distinct_hosts`) — monitors the primary and
  promotes a replica automatically if it goes down.

Each `redis` task also registers a `current-master`-gated `redis` Consul
service (a script check querying Sentinel directly) so consumers can discover
the writer the same way `postgres`'s consumers discover its leader — resolve
`redis.service.consul`, not a specific host, and it always points at whoever
Sentinel currently considers master. There's also an always-healthy
`redis-node` service (tagged `primary-group`/`replica-group`) for anything
that specifically needs every node, like `seaweedfs-filer`'s Sentinel client
config.

**Storage path asymmetry, worth knowing before debugging a resync:** the
primary persists to NFS (`/Volumes/Cosmonautical/seaweedfs-filer-redis` —
named for its main consumer, `seaweedfs-filer`'s metadata store), but
replicas persist to *local* disk (`/opt/seaweedfs/redis-local/data`). This
is intentional, not a leftover — replicas can always re-sync fully from the
primary, so there's no need to pay NFS latency on every replica write, only
on the primary's.

Used by [`seaweedfs-filer`](../seaweedfs-filer) as its filer metadata store
and by `nextcloud`'s app-level caching — see each consumer's README for how
it's wired in.

## Consul KV keys

| Key | Used for |
|---|---|
| `redis/PASSWORD` | `requirepass`/`masterauth`, shared across primary/replica/sentinel |

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
