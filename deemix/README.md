# deemix

Runs [deemix](https://github.com/bambanah/deemix-docker)
(`ghcr.io/bambanah/deemix:latest`) via the `container` driver (Apple's
`container` CLI, not Docker) — a Deezer downloader web UI, single-user mode,
port `6595`. Config and downloaded files both live on NFS
(`/Volumes/Cosmonautical/deemix/{config,downloads}`).

No Traefik tags — internal-only.

## Consul KV keys

None — no `template`/`{{ key ... }}` references in this job's spec.

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
