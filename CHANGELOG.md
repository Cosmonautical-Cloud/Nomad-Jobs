# Changelog

History and rationale for jobs managed in this repo. Job spec (`.nomad.hcl`)
files themselves stay lean — the "why" behind a decision, a fix, or a
workaround lives here instead, dated, so it's still findable without reading
through commit-by-commit diffs. This replaces the older convention (still
used in the separate hand-deployed `nomad-jobs` repo) of writing that
history as long inline HCL comments — same departure the jellify sibling
repo made.

Newest entries first, grouped by job.

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
