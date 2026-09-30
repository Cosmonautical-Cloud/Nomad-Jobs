# seaweedfs

The `master`/`volume` tiers of a [SeaweedFS](https://github.com/seaweedfs/seaweedfs)
cluster, deployed as a Nomad `system` job — one alloc of each group on every
matching client, which in practice means one `master` and one `volume` on
each of the three cosmonautical hosts (`cassiopeia`, `taurus`,
`betelgeuse`), hardcoded as each other's peers/master list.

- **`masters`** — the metadata/coordination tier (`weed master`), one per
  host, `-peers` pointing at all three for consensus.
  `-defaultReplication=001` replicates every volume to one other node by
  default. Registers as the `seaweedfs-master` Consul service.
- **`volume-nodes`** — the actual block storage tier (`weed volume`),
  unbounded size (`-max=0`), storing to local disk
  (`/opt/seaweedfs/data`) on each host.

Paired with [`seaweedfs-filer`](../seaweedfs-filer) (the filesystem-semantics
+ S3 layer on top of this raw object store) and
[`seaweedfs-nfs-backup`](../seaweedfs-nfs-backup) (continuous backup off the
filer). For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
