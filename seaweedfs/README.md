# seaweedfs

The [SeaweedFS](https://github.com/seaweedfs/seaweedfs) stack: the raw
object store, the filer + S3 gateway on top of it, and a continuous backup
off the filer — each its own Nomad job and Terraform resource, with all
three specs kept side by side in this folder (see the repo README's "Stack
folders").

| Job | Spec | Type | What it does |
|---|---|---|---|
| `seaweedfs` | [`seaweedfs.nomad.hcl`](seaweedfs.nomad.hcl) | system | `master`/`volume` tiers on every host |
| `seaweedfs-filer` | [`seaweedfs-filer.nomad.hcl`](seaweedfs-filer.nomad.hcl) | service | Filesystem layer (`weed filer`) + S3 gateway (`weed s3`) |
| `seaweedfs-nfs-backup` | [`seaweedfs-nfs-backup.nomad.hcl`](seaweedfs-nfs-backup.nomad.hcl) | service | Continuous `weed filer.backup` to the NAS |

## seaweedfs

The `master`/`volume` tiers of the cluster, deployed as a Nomad `system`
job — one alloc of each group on every matching client, which in practice
means one `master` and one `volume` on each of the three cosmonautical hosts
(`cassiopeia`, `taurus`, `betelgeuse`), hardcoded as each other's
peers/master list.

- **`masters`** — the metadata/coordination tier (`weed master`), one per
  host, `-peers` pointing at all three for consensus.
  `-defaultReplication=001` replicates every volume to one other node by
  default. Registers as the `seaweedfs-master` Consul service.
- **`volume-nodes`** — the actual block storage tier (`weed volume`),
  unbounded size (`-max=0`), storing to local disk
  (`/opt/seaweedfs/data`) on each host.

## seaweedfs-filer

The filesystem-semantics layer on top of `seaweedfs`'s raw object storage
(`weed filer`), plus an S3-compatible gateway (`weed s3`) in front of it.

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

**Buckets aren't created automatically** — Litestream itself doesn't issue
`CreateBucket`, and this filer had no buckets besides the built-in
`.system` one until 2026-09-30, when `slskd`/`sabnzbd`'s Litestream
replication was found to have been failing silently for hours with
`NoSuchBucket` errors for exactly this reason. Each job that replicates
here now creates its own bucket via a prestart task
(`weed shell -filer=<this job's address> s3.bucket.create -name <bucket>`,
safe to re-run) rather than assuming it pre-exists — see `slskd`'s or
`sabnzbd`'s job spec.

## seaweedfs-nfs-backup

Long-running (not periodic — `weed filer.backup` streams continuously)
incremental backup of `seaweedfs-filer`'s entire filer namespace out to the
NAS's NFS share (`/Volumes/Cosmonautical/seaweedfs-backup/data`), pinned to
`cassiopeia.cosmonautical.cloud`. Excludes `/sabnzbd` and `/lidarr/config` —
high-churn, low-value paths not worth the continuous backup I/O.

Migrated from the legacy repo's `seaweedfs-backup.nomad.ncl`, renamed to
match its job ID (`seaweedfs-nfs-backup`), no content changes.

## Consul KV keys

| Key | Used by | Used for |
|---|---|---|
| `redis/PASSWORD` | `seaweedfs-filer` | Sentinel-backed filer metadata store auth |
| `seaweedfs-s3/ACCESS_KEY` | `seaweedfs-filer` | S3 gateway's `litestream` identity access key |
| `seaweedfs-s3/SECRET_KEY` | `seaweedfs-filer` | S3 gateway's `litestream` identity secret key |

`seaweedfs` and `seaweedfs-nfs-backup` have no `template`/`{{ key ... }}`
references.

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
