# Agent operating guide — cosmonautical Nomad-Jobs

`README.md` explains the Terraform structure and conventions of this repo.
This file is the operational context an agent needs but that doesn't belong
in a human-facing README: cluster topology, safety rules, and gotchas
specific to working here.

## This repo vs. the others

- **This repo** (`Cosmonautical-Cloud/Nomad-Jobs`) — Terraform-managed job
  specs for the **cosmonautical** datacenter, deployed via Semaphore (see
  README's "Wiring into Semaphore"). Once a job has a directory here, it's
  edited and deployed here — never by hand against the cluster's HTTP API.
- **`~/Workspace/nomad-jobs`** — the older, hand-deployed sibling repo for
  this same **cosmonautical** datacenter. Its own `.agents/AGENTS.md`
  documents the HTTP-API deploy workflow (parse → plan → register) and a set
  of macOS/TCC/driver gotchas — read that file's "Known gotchas" section in
  full before debugging anything odd here; don't re-litigate a gotcha
  already diagnosed there. A job moves out of that repo and into this one
  once it's brought under Terraform.
- **`~/Workspace/Jellify/Nomad-Jobs`** — the equivalent Terraform-managed
  repo for the **jellify** datacenter. Same structure/conventions as this
  repo. Its own `.agents/AGENTS.md` documents jellify's mixed-arch host
  table and constraint patterns — not relevant here, since cosmonautical is
  all-macOS/arm64, but useful if a job ever needs to move between
  datacenters.
- **`~/Workspace/Nomadable`** — the Ansible playbook that *provisions* Nomad
  + Consul onto hosts (installs the agent, not job workloads). Cosmonautical
  hosts are all macOS, dispatched to `~/Workspace/Nomadintosh` (the macOS
  child playbook, Homebrew + LaunchAgents).

## Cluster topology — cosmonautical

- Three Nomad + Consul server/client nodes, all macOS/Darwin Mac
  minis/Studios: `cassiopeia`, `taurus`, `betelgeuse` — reachable via SSH
  using those short hostnames.
- **cosmonautical and jellify are datacenters within the same single Nomad
  region** — confirmed via `curl 127.0.0.1:4646/v1/nodes` from `cassiopeia`
  listing both datacenters' hosts. Consul is likewise shared cluster-wide
  (ACLs disabled). This is why this repo's Terraform backend `path`
  (`nomad-jobs-cosmonautical`) is deliberately distinct from the jellify
  repo's (`nomad-jobs`) — see `versions.tf`. It also means job IDs must
  stay unique across *both* repos, not just within this one.
- Nomad HTTP API at `127.0.0.1:4646`, Consul at `127.0.0.1:8500` — both only
  reachable from *on* a host, so SSH in first for any direct API work
  (imports, live-drift checks).
- **No `nomad` or `consul` CLI installed on any host.** No `docker`, no
  `journalctl`, no `/proc` (it's macOS). Direct API work goes through curl
  or a scripting language's HTTP client.
- Most workloads run via the `raw_exec` driver (native macOS binaries via
  Homebrew), some via `driver = "container"` (Apple's `container` CLI, not
  Docker).

## Secrets (Consul KV)

Same pattern as the legacy repo — nothing here manages secrets via Terraform
(no `consul_keys` resource in `main.tf`). Every credential is populated by
hand into Consul KV ahead of a job's first deploy, then referenced from a
`template` block inside the `.nomad.hcl` file:

```hcl
template {
  data        = <<EOT
PASSWORD={{ key "app/PASSWORD" }}
HOST={{ range service "postgres" }}{{ .Address }}{{ end }}
EOT
  destination = "secrets/app.env"
  env         = true
}
```

Convention here (unlike jellify's per-job `jellify/<job>/<KEY_NAME>`
namespacing): keys live under `<app-or-shared-concern>/<KEY_NAME>`, and some
prefixes are deliberately shared across multiple jobs rather than
per-job-namespaced — e.g. `redis/PASSWORD`, `s3/KEY_ID`, `s3/APPLICATION_KEY`,
`s3/ENDPOINT`, and `smtp/*` are all read by more than one job here
(`nextcloud`, `nextcloud-cron`, `nextcloud-preview-generate`, and
`nextcloud-roms-scan` all reference `nextcloud/DB_PASSWORD` and
`redis/PASSWORD`). Don't rename or re-namespace these on migration — they're
live keys already populated for the legacy deploy.

- **List keys under a prefix without reading values:**
  `curl 'http://127.0.0.1:8500/v1/kv/<prefix>?keys'`
- **Read one value** (only when actually needed): `curl
  'http://127.0.0.1:8500/v1/kv/<full/key/path>?raw'`
- Avoid printing a secret's raw value into chat/logs unless the user is
  actively debugging that exact value.

## Known gotchas

Don't duplicate the legacy repo's gotcha list here — read
`~/Workspace/nomad-jobs/.agents/AGENTS.md`'s "Known gotchas" section, all of
which still apply (same hosts, same OS, same drivers). Most relevant to
`nextcloud` and its four periodic siblings specifically:

- **NFS mounts — concurrent I/O contention** (gotcha #5 there). The NAS's
  disk I/O is a shared bottleneck across all NFS clients simultaneously, and
  because these mounts are `hard`, a task can block indefinitely rather than
  fail cleanly under load. The five nextcloud jobs' schedules are staggered
  specifically to avoid overlapping:

  | Job | Schedule (UTC) |
  |---|---|
  | `nextcloud-cron` | `*/5 * * * *` |
  | `nextcloud-preview-generate` | `*/15 * * * *` |
  | `nextcloud-roms-scan` | `0 0 * * *` |
  | `nextcloud-s3-backup` | `0 3 * * *` |

  When adding a new periodic job that touches the NAS heavily, stagger its
  schedule against this table too.
- **NFS mounts — UID-squashing** (gotcha #4 there, open/paused). Files
  written over the NAS's NFS mounts come back owned by uid 977/gid 988, not
  the real writing user, and `chown` is rejected — relevant if a future
  nextcloud-adjacent job depends on real file ownership over
  `/Volumes/Cosmonautical`.
- **macOS TCC gates on external/NFS volume writes and the `java` driver**
  (gotchas #6/#6b/#7/#7b there) — not currently hit by any of these five
  jobs (all use `raw_exec` + Homebrew PHP/Caddy, already working), but worth
  knowing before adding a new task here.

## Shared infra tier (postgres / redis / traefik / seaweedfs)

As of 2026-09-30 this repo also owns the cluster's shared backing services,
not just app jobs:

- **`traefik` fronts both datacenters, not just cosmonautical** — its
  `minecraft`/`bedrock`/`valheim-*` ports and `update-port-forward` task
  exist to route to jobs running in **jellify** (`Jellify/Nomad-Jobs`'s
  `minecraft`/`valheim`), since Consul (and the UniFi router) are shared
  cluster-wide. There is deliberately only one Traefik in the whole cluster.
  See `traefik/README.md`.
- **`postgres` and `redis` are both HA (Patroni / Sentinel)** — always
  discover the writer through the plain `postgres`/`redis` Consul service
  names (gated to the current leader/master), never a specific host or the
  always-healthy `postgres-node`/`redis-node` variants, unless a job
  specifically needs every node.
- **`seaweedfs` is a `system` job** — one alloc per group per eligible host
  automatically, not a fixed `count`. Its `-peers`/`-mserver` host lists are
  hardcoded to all three cosmonautical hosts, so it can't currently expand
  past this datacenter's three nodes without editing those flags too.

## Terraform import workflow

A job already running when brought under Terraform needs `terraform import
nomad_job.<id> <id>` before the first `apply`, and the first `plan` after
import must be a true no-op — verified via the Nomad HTTP API's
`/v1/jobs/parse` + `/v1/job/<id>/plan` directly against the live cluster
before trusting a spec, not just by inspecting the HCL. See README's
"Bringing an already-running job under Terraform" for the exact commands for
the five nextcloud jobs.

## Don't

- Don't hand-deploy a job spec that lives in this repo directly against the
  cluster's HTTP API — it goes through Terraform/Semaphore, or state drifts
  out from under the next `plan`.
- Don't trust `terraform plan` output at face value for an import — verify
  the specific job's portion reads as a true no-op (or only the intended
  change) against the live cluster's `/v1/job/<id>/plan` too.
- Don't assume a host-side `/opt/nomad/jobs/*` copy reflects current
  reality — verify against this repo and what's actually registered
  (`GET /v1/job/<name>`). Staleness cutoff: if a host-side file hasn't been
  modified in the last week, it's not worth diffing.
- Don't run `ansible-playbook` (Nomadable or Nomadintosh) against a
  live/in-use host without asking first.
- Don't reuse a job ID or Consul KV prefix already in use by the jellify
  sibling repo — this cluster's Nomad region and Consul KV are shared
  across both datacenters.
