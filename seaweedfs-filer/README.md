# seaweedfs-filer

The filesystem-semantics layer on top of [`seaweedfs`](../seaweedfs)'s raw
object storage (`weed filer`), plus an S3-compatible gateway (`weed s3`) in
front of it.

The filer stores its own metadata in [`redis`](../redis) via Sentinel
(`redis2_sentinel`, discovering all three sentinels through the
`redis-sentinel` Consul service, `database 1`) rather than the default
embedded LevelDB (`leveldb2` explicitly disabled) — metadata survives a
filer restart/relocation independent of local disk.

The S3 gateway's one configured identity is named `litestream` — this
bucket exists specifically as a [Litestream](https://litestream.io/)
replication target for SQLite-backed jobs elsewhere in the cluster, not as
general-purpose S3 storage (that's what `nextcloud-s3-backup`'s B2 bucket
and the dedicated `s3/*` Consul KV secrets are for).

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
