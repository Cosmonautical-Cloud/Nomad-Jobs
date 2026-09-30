# radarr

Runs Radarr (native macOS `.app` bundle, Homebrew-adjacent install), no host
constraint, `priority = 60`. No Traefik tags — internal-only, part of the
*arr stack alongside [`lidarr`](../lidarr) and [`sonarr`](../sonarr).

Unlike `lidarr`, this job has no prestart config-restore or DB-backup
sidecar task — worth confirming with the legacy repo's `.agents/AGENTS.md`
whether that's intentional (lower-value data) or just not yet added, before
assuming parity with `lidarr`'s persistence story.

## Consul KV keys

None — no `template`/`{{ key ... }}` references in this job's spec.

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
