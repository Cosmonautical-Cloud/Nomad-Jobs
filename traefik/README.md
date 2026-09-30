# traefik

The cluster's single ingress: TLS termination (Let's Encrypt via
Cloudflare's DNS-01 challenge, `cf-dns` resolver) and HTTP/TCP/UDP routing,
service discovery entirely through Consul Catalog (`exposedByDefault =
false` — a service must opt in with `traefik.enable=true` tags, see
`nextcloud.nomad.hcl` for the pattern).

**This is the ingress for both datacenters, not just cosmonautical** — even
though this job's own `datacenters = ["cosmonautical"]`, its `web`/`postgres`
entrypoints route any tagged Consul service regardless of which datacenter
registered it (Consul is cluster-wide, see `.agents/AGENTS.md`), and its
`minecraft`/`bedrock`/`valheim-*` ports plus the `update-port-forward` task
exist specifically to front jobs that run in **jellify**
(`Jellify/Nomad-Jobs`'s `minecraft`/`valheim`). Don't stand up a second
Traefik in jellify without checking here first — it would fight this one for
the UniFi port-forward rules `update-port-forward` maintains.

Notable pieces:

- **`update-port-forward`** (prestart) — keeps the UniFi router's port-forward
  rules pointed at whichever host currently holds this job's alloc, reading
  target Nomad variables (`nomad/jobs/minecraft`, `nomad/jobs/valheim`) for
  the rule IDs to update. Only runs if those variables are set, so it's a
  no-op when minecraft/valheim aren't deployed.
- **`seed-data`** (prestart) / the `traefik` task's background `sync_loop` —
  ACME cert storage (`acme.json`) and the Consul-catalog-independent
  `dynamic.yml` are synced to/from `/Volumes/Cosmonautical/traefik/persistent`
  every 5 minutes, so a redeploy to a different host doesn't re-trigger a
  fresh ACME issuance.
- **`websecure`'s `readTimeout: 3600s`** — default (1m) was too short for
  large Nextcloud DAV uploads under concurrent NAS load; see
  `CHANGELOG.md` for the incident this was confirmed against.
- **`postgres` entrypoint (`:15432`)** — TCP passthrough to whichever
  Postgres node is currently leader, gated by [`postgres`](../postgres)'s
  `/primary`-checked Consul service tags.

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
