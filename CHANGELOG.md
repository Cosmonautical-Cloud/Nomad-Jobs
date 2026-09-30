# Changelog

History and rationale for jobs managed in this repo. Job spec (`.nomad.hcl`)
files themselves stay lean — the "why" behind a decision, a fix, or a
workaround lives here instead, dated, so it's still findable without reading
through commit-by-commit diffs. This replaces the older convention (still
used in the separate hand-deployed `nomad-jobs` repo) of writing that
history as long inline HCL comments — same departure the jellify sibling
repo made.

Newest entries first, grouped by job.

## repo-wide

### 2026-09-30

- **All three of this repo's first commits were actually applied by
  Semaphore** (its Terraform App plan/approve/apply flow), not just
  committed — confirmed by reading Terraform state directly out of Consul
  (`nomad-jobs-cosmonautical` key): every resource this repo defines is
  present. No `terraform import` step happened first; see the root
  README's "How these ended up under Terraform" for the full story of why
  that turned out safe for 26 of 27 jobs and not for `guacamole` (below).
  This repo (not the legacy `nomad-jobs` repo) is now the thing actually
  driving the cluster for every job it covers.
- Added `renovate.json` — Docker image tags (custom regex manager, Nomad
  job specs aren't a format Renovate parses natively) and Terraform
  provider versions (native `config:recommended` support) get automatic PRs.
  Also tracks release versions for the checksum-pinned binary downloads
  (`keycloak`, `lidarr`, `slskd`, `semaphore`) via `github-releases` — those
  PRs are a signal only, they can't recompute the sha256 a human still has
  to update by hand.

## guacamole

### 2026-09-30

- **Pulled out of `main.tf`, not currently deployed.** Its first real
  `apply` (part of the same-day batch above) tried to schedule all 3 of its
  tasks for the first time — unlike every other job in that batch, this one
  had apparently never actually been successfully registered before, so
  this wasn't a no-op re-registration like the rest. The cluster's 3
  cosmonautical hosts were all near capacity from the rest of the batch
  starting up at the same time, so `guacamole`'s allocation got stuck
  blocked/unscheduled (confirmed via a blocked evaluation showing
  `ResourcesExhausted` on all 3 nodes). Rather than leave it half-working,
  the `nomad_job.guacamole` resource was removed from `main.tf` — the job
  spec and its README stay as reference. Re-add it once there's a reason to
  actually test it, ideally after confirming the cluster has free capacity.

## audiomuse-ai / openldap / deemix / dispatcharr / guacamole / jellyfin / keycloak / lidarr / ollama / open-webui / radarr / sabnzbd / seerr / semaphore / slskd / sonarr

### 2026-09-30

- **Brought under Terraform**, migrated unmodified from the legacy
  `nomad-jobs` repo. This is the rest of the cluster's active jobs — with
  this batch plus the two prior ones (nextcloud stack, core infra tier),
  every job that was in the legacy repo is now mirrored here (28 total).
  The legacy repo remains the deployed source of truth until each job is
  actually `terraform import`ed (none are yet).
  - `auth.nomad.hcl` → directory/file renamed to `openldap` to match its
    actual job ID (`job "openldap"`) — same situation as
    `seaweedfs-nfs-backup` from the prior batch, the legacy filename didn't
    match its own job ID. The `auth.cosmonautical.cloud` hostname actually
    belongs to `keycloak`, not this job.
  - `lidarr.nomad`, `radarr.nomad`, `sabnzbd.nomad`, `slskd.nomad`,
    `sonarr.nomad` → renamed to `.nomad.hcl` for extension consistency;
    content unchanged.
  - **`jellyfin`, `open-webui`, and `seerr` all run as cosmonautical jobs
    but serve `*.jellify.app` domains** — not a mistake, `traefik` is a
    single cluster-wide ingress (see its README) and domain names follow
    the app, not the datacenter it happens to run in.
  - **Security fix (the one deliberate deviation from "migrate unmodified"
    in this repo)**: `keycloak.nomad.hcl` had `KEYCLOAK_ADMIN_PASSWORD =
    "changeme"` hardcoded in plaintext in its `env` block — the only literal
    secret found anywhere in this repo (confirmed via a full-repo scan,
    see `.agents/AGENTS.md`'s "This repo is public" section), and this repo
    is public. Found before push, fixed before push: wired to the
    pre-existing Consul KV key `keycloak/BOOTSTRAP_ADMIN_PASSWORD` via
    `template` instead, same pattern as every other credential here.
  - All sixteen were already registered/running before this migration —
    each needs `terraform import` before the first `apply` (see README's
    "Bringing an already-running job under Terraform"). `keycloak` and
    `semaphore` carry above-average blast radius (auth; the eventual CI
    system for this repo) if an import or plan goes wrong.

## postgres / postgres-backup / redis / traefik / seaweedfs / seaweedfs-filer / seaweedfs-nfs-backup

### 2026-09-30

- **Brought under Terraform**, migrated unmodified from the legacy
  `nomad-jobs` repo (`postgres/postgres.nomad.hcl`,
  `postgres/postgres-backup.nomad.hcl`, `redis.nomad.hcl`, `traefik.nomad`,
  `seaweedfs/seaweedfs.nomad.hcl`, `seaweedfs/seaweedfs-filer.nomad.hcl`,
  `seaweedfs/seaweedfs-backup.nomad.ncl`). No behavioral changes, just the
  move — this is the shared infra tier the `nextcloud` jobs (and future app
  jobs) already depend on via Consul service discovery, now brought under
  the same management as everything else here.
  - `seaweedfs-backup.nomad.ncl` → directory/file renamed to
    `seaweedfs-nfs-backup` to match its actual job ID
    (`job "seaweedfs-nfs-backup"`), per this repo's job-ID-based naming
    convention — the legacy repo's filename didn't match its own job ID.
  - `traefik.nomad` → renamed to `traefik.nomad.hcl` for extension
    consistency with every other job spec here; content unchanged.
  - `seaweedfs/replication.toml` was **not** copied over — confirmed (via
    the legacy repo's own README) to be a dead leftover duplicate of the
    `template` block already embedded in `seaweedfs-nfs-backup`'s job spec,
    never read by anything.
  - All seven were already registered/running before this migration —
    each needs `terraform import` before the first `apply` (see README's
    "Bringing an already-running job under Terraform"). `traefik` and
    `seaweedfs` carry the widest blast radius of anything in this repo if
    an import or plan goes wrong — front-load care there.

## nextcloud / nextcloud-cron / nextcloud-preview-generate / nextcloud-s3-backup / nextcloud-roms-scan

### 2026-09-30

- **Brought under Terraform**, migrated unmodified from the legacy
  `nomad-jobs` repo's `nextcloud/` directory (hand-deployed against the
  cluster's HTTP API). All five specs moved as-is — no behavioral changes
  as part of this migration, just the move. Each job keeps its own
  top-level directory and its own `nomad_job` resource in `main.tf`, per
  this repo's one-directory-per-job convention (see README's "Why five
  directories for one app").
  - `nextcloud` — the main service job (Caddy + PHP-FPM on `:8083`,
    Traefik-routed at `drive.cosmonautical.cloud`).
  - `nextcloud-cron` (`*/5 * * * *`), `nextcloud-preview-generate`
    (`*/15 * * * *`), `nextcloud-s3-backup` (`0 3 * * *`), and
    `nextcloud-roms-scan` (`0 0 * * *`) — periodic batch jobs, schedules
    deliberately staggered against each other and the main service to
    avoid saturating the NAS's NFS mounts under concurrent I/O (see
    `.agents/AGENTS.md`, carried over from the legacy repo's own gotcha
    #5).
  - All five were already registered/running before this migration —
    needs `terraform import` before the first `apply` for each (see
    README's "Bringing an already-running job under Terraform").
