# jellyfin

Runs Jellyfin (native macOS `.app` bundle) pinned to
`cassiopeia.cosmonautical.cloud`, `priority = 60` (above the Nomad default
of 50 — preferred over lower-priority jobs when the cluster is resource-
constrained). Routed at `jellyfin.jellify.app`.

**Runs in the cosmonautical datacenter but serves a `jellify.app` domain** —
this isn't a typo. [`traefik`](../traefik) is the single ingress for both
datacenters (see its README), and domain names here follow the app/brand,
not which datacenter physically runs the job. Same pattern as
[`open-webui`](../open-webui) (`ai.jellify.app`) and [`seerr`](../seerr)
(`seerr.jellify.app`).

## Consul KV keys

None — no `template`/`{{ key ... }}` references in this job's spec.

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
