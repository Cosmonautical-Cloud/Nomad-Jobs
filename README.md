# Nomad-Jobs

A Terraform plan for the services and jobs we run on Nomad in the
**cosmonautical** datacenter, deployed via Semaphore: merges to `main`
trigger `terraform plan`, surfaced in Semaphore's UI as an approval gate
before `apply`. This is the canonical source for any job managed here — once
a job has a directory in this repo, its spec is edited and deployed here,
not by hand against the cluster's HTTP API.

Nomad job specs that *aren't* migrated to Terraform yet still live in the
separate, older `nomad-jobs` repo and are deployed by hand against the
cluster's HTTP API. A job moves out of that repo and into this one when
it's brought under Terraform, at which point its `.nomad.hcl` file's
canonical copy lives here. See this repo's sibling for the **jellify**
datacenter: [`Jellify/Nomad-Jobs`](https://github.com/Jellify-Music/Nomad-Jobs)
— same structure and conventions, different datacenter.

## Structure

```
.
├── main.tf                        one nomad_job resource per job, shared state
├── versions.tf
├── nextcloud/
│   └── nextcloud.nomad.hcl
├── nextcloud-cron/
│   └── nextcloud-cron.nomad.hcl
├── nextcloud-preview-generate/
│   └── nextcloud-preview-generate.nomad.hcl
├── nextcloud-s3-backup/
│   └── nextcloud-s3-backup.nomad.hcl
├── nextcloud-roms-scan/
│   └── nextcloud-roms-scan.nomad.hcl
├── postgres/
│   └── postgres.nomad.hcl
├── postgres-backup/
│   └── postgres-backup.nomad.hcl
├── redis/
│   └── redis.nomad.hcl
├── traefik/
│   └── traefik.nomad.hcl
├── seaweedfs/
│   └── seaweedfs.nomad.hcl
├── seaweedfs-filer/
│   └── seaweedfs-filer.nomad.hcl
└── seaweedfs-nfs-backup/
    └── seaweedfs-nfs-backup.nomad.hcl
```

This is a single root module — every job is one `nomad_job` resource in the
same `main.tf`, sharing one Consul-backed state, and Semaphore only needs one
Terraform App (pointed at the repo root) to plan/apply everything. The
tradeoff: `plan`/`apply` always cover every job at once, so a change to one
job's spec shows up in the same diff as everyone else's, and approving an
apply applies all of them together. Read the whole plan before approving —
there's no way to approve just one job's change here. If a job ever needs to
be isolated from that blast radius (frequent changes, higher risk, whatever
the reason), split it back out into its own directory with its own
`main.tf`/`versions.tf`/backend `path`, same pattern as before.

Each resource is named to match its job's actual Nomad job ID (the
`job "..."` block's name, not the directory) — that's what makes
`terraform import <address> <job-id>` read intuitively, e.g.
`nomad_job.nextcloud` importing job ID `nextcloud`,
`nomad_job.nextcloud-cron` importing job ID `nextcloud-cron`. The
`hashicorp/nomad` provider's `nomad_job` resource is already the whole
abstraction here (one `jobspec` string in, one job registered out), so
there's no wrapper module — one would only add indirection with no behavior
of its own.

`jobspec` loads each job's `.nomad.hcl` file via `file()` rather than
embedding it as a Terraform heredoc — Nomad's own
`${NOMAD_ALLOC_DIR}`/`${NOMAD_TASK_DIR}`-style interpolation syntax would
otherwise collide with Terraform's own `${...}` template interpolation
inside a heredoc string.

Adding a new job: create `<job>/<job>.nomad.hcl` with that job's spec, then
add a resource block to `main.tf`:

```hcl
resource "nomad_job" "<job-id>" {
  jobspec = file("${path.module}/<job>/<job>.nomad.hcl")
}
```

## Why five directories for one app

`nextcloud`, `nextcloud-cron`, `nextcloud-preview-generate`,
`nextcloud-s3-backup`, and `nextcloud-roms-scan` are all part of the same
Nextcloud deployment (same app config, same Postgres/Redis/S3 backing
services), but each is registered as its own Nomad job, so each gets its own
top-level directory here — one directory per job ID, same rule as every
other job in this repo (and its jellify sibling). The five jobs' schedules
are deliberately staggered against each other and against the main service's
own load, to avoid saturating the NAS's NFS mounts under concurrent I/O — see
`.agents/AGENTS.md` for the schedule table and the underlying gotcha.

## Changelog

Job spec (`.nomad.hcl`) files here stay lean — no long inline comment blocks
explaining *why* something is the way it is, or the history of how it got
there. That belongs in [`CHANGELOG.md`](CHANGELOG.md) instead, dated, grouped
by job. A comment in a `.nomad.hcl` file should only ever describe something
non-obvious about its *current* state in a line or two; anything more (a
fix, a migration, a "confirmed on this date" note, a decision between
alternatives) goes in the changelog. This is a deliberate departure from the
separate hand-deployed `nomad-jobs` repo's convention (heavy inline
comments, no changelog) — that repo isn't changing retroactively, but
anything brought under Terraform here follows this convention going
forward.

## Why Consul for state

The cluster already runs Consul with ACLs disabled, shared across every
Nomad datacenter (cosmonautical and jellify both) — so it doubles as state
storage with no new infra. Same reasoning for the `nomad` provider's
`address`: every host in the cluster (either datacenter) reaches
`127.0.0.1:4646` locally, and ACLs being off means there's no token to
configure. Because state is genuinely shared cluster-wide, this repo's
backend `path` (`nomad-jobs-cosmonautical`) is deliberately distinct from
the jellify repo's (`nomad-jobs`) — see `versions.tf`.

## Bringing an already-running job under Terraform

Every job in this repo was already registered and running (real user data —
Nextcloud's Postgres/Redis-backed instance, the shared Postgres/Redis/
SeaweedFS infra tier, the cluster's own ingress) before its directory
existed here, having been deployed by hand against the cluster's HTTP API
from the legacy `nomad-jobs` repo. Applying any of their configs for the
first time must not re-trigger a deploy. Import the existing job into state
instead of creating it fresh, then confirm a plan is a true no-op before
ever running apply:

```sh
terraform init
terraform import nomad_job.nextcloud nextcloud
terraform import nomad_job.nextcloud-cron nextcloud-cron
terraform import nomad_job.nextcloud-preview-generate nextcloud-preview-generate
terraform import nomad_job.nextcloud-s3-backup nextcloud-s3-backup
terraform import nomad_job.nextcloud-roms-scan nextcloud-roms-scan
terraform import nomad_job.postgres postgres
terraform import nomad_job.postgres-backup postgres-backup
terraform import nomad_job.redis redis
terraform import nomad_job.traefik traefik
terraform import nomad_job.seaweedfs seaweedfs
terraform import nomad_job.seaweedfs-filer seaweedfs-filer
terraform import nomad_job.seaweedfs-nfs-backup seaweedfs-nfs-backup
terraform plan   # must show "No changes" - if it doesn't, stop and diff by hand first
```

Before importing, confirm each job is actually still registered as expected
(`GET /v1/job/<id>` against the live cluster) — the legacy repo's copies can
drift from what's actually deployed, and only files modified within the last
week are worth trusting without a fresh diff (see `.agents/AGENTS.md`).
`traefik` and `seaweedfs` are worth extra care before importing — they're
the cluster's ingress and shared storage tier respectively, so a bad import
(or a plan that isn't actually a no-op) has a wide blast radius if `apply`
ever ran against it by mistake.

Only once `plan` looks right should Semaphore (or a human) ever run `apply`.

## Wiring into Semaphore

1. Add a single Terraform "App" pointed at this repo, working directory set
   to the repo root (not a job subdirectory — the `.tf` files live there
   now).
2. No extra credentials needed in the task template — Consul and Nomad are
   both unauthenticated on `127.0.0.1`, reachable because Semaphore itself
   runs as a Nomad job on one of the cluster's hosts.
3. Trigger the app on every merge to `main`, with the plan step requiring
   manual approval before apply.
