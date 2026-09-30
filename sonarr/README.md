# sonarr

Runs Sonarr (native macOS `.app` bundle), no host constraint, `priority =
60`. No Traefik tags — internal-only, part of the *arr stack alongside
[`lidarr`](../lidarr) and [`radarr`](../radarr). Same note as `radarr`: no
prestart config-restore or DB-backup sidecar here, unlike `lidarr` — not
confirmed whether that's intentional.

## Consul KV keys

None — no `template`/`{{ key ... }}` references in this job's spec.

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
