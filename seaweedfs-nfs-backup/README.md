# seaweedfs-nfs-backup

Long-running (not periodic — `weed filer.backup` streams continuously)
incremental backup of [`seaweedfs-filer`](../seaweedfs-filer)'s entire
filer namespace out to the NAS's NFS share
(`/Volumes/Cosmonautical/seaweedfs-backup/data`), pinned to
`cassiopeia.cosmonautical.cloud`. Excludes `/sabnzbd` and `/lidarr/config` —
high-churn, low-value paths not worth the continuous backup I/O.

**Job ID doesn't match its directory/file name on purpose**: the job is
`seaweedfs-nfs-backup` (matches this repo's job-ID-based naming convention —
see root README), but the legacy repo's source file was named
`seaweedfs-backup.nomad.ncl`. Copied over renamed, no content changes.

## Consul KV keys

None — no `template`/`{{ key ... }}` references in this job's spec.

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
