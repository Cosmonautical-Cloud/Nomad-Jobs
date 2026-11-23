# Changelog

History and rationale for jobs managed in this repo. Job spec (`.nomad.hcl`)
files themselves stay lean — the "why" behind a decision, a fix, or a
workaround lives here instead, dated, so it's still findable without reading
through commit-by-commit diffs. This replaces the older convention (still
used in the separate hand-deployed `nomad-jobs` repo) of writing that
history as long inline HCL comments — same departure the jellify sibling
repo made.

Newest entries first, grouped by job.

## nextcloud

### 2026-11-20

- **Nextcloud 34.0.6 → 35.0.3 (major), with its checksum.** Renovate #27
  was merged as-is despite its PR note, so it bumped the version but left
  34.0.6's sha256. Job v85 then failed every artifact download, with v84
  already stopped, so Nextcloud was down. The new checksum matches
  upstream's `nextcloud-35.0.3.tar.bz2.sha256`. 35 supports PHP 8.3-8.5
  (the job uses 8.4) and upgrades from 34.0.

### 2026-11-18

- **Version bumps now actually upgrade the server.** `start.sh` only
  unpacked the release when `version.php` was missing, and the sticky
  ephemeral disk carries the previous alloc's tree forward. So the 34.0.6
  bump below left the service on 34.0.4 (the periodic jobs unpack fresh
  each run and did get 34.0.6). The script now re-extracts whenever
  `version.php` doesn't match the pinned `release`. `config` and
  `custom_apps` are symlinks into the alloc dir and the NAS, so they
  survive the `rm -rf`.
- **`occ upgrade` timeout 90s → 25m, `check_restart` grace 90s → 30m.**
  `occ upgrade` also updates App Store apps, copying them onto the NFS
  `custom_apps`. On the 34.0.6 rollout the 90s `kill -9` landed mid-copy
  and left the Music app with 323 of its 467 files. Every `occ` call then
  failed on a missing class, and the job went `failed` until the app was
  re-extracted by hand. The check grace has to outlast the upgrade, or
  `check_restart` kills it the same way.

## semaphore

### 2026-11-20

- **Semaphore follows a Patroni failover.** `config.json` held the
  primary's literal IP, rendered by the `bootstrap` prestart task, which
  never re-renders. When postgres v28 (the `shared_buffers` bootstrap
  change) replaced all three Patroni allocs, the primary moved orion →
  taurus. Semaphore kept writing to orion and failed with `cannot execute
  ... in a read-only transaction` until its alloc was restarted by hand. It
  now uses `postgres.service.consul:5432`, like Keycloak and Dispatcharr.
  Consul DNS returns only the member whose `primary` check passes, and
  every new connection re-resolves it. The other Postgres-backed jobs
  render the address in their main task, so a failover re-renders the
  template and restarts them onto the new primary.

## repo-wide

### 2026-11-20

- **Renovate now tracks Nextcloud, Caddy and rclone.** They're
  checksum-pinned downloads like Keycloak/Lidarr/slskd/Semaphore, but no
  custom manager matched them, so Renovate never saw them at all. Each now
  has a `github-releases` regex manager (`nextcloud/server`,
  `caddyserver/caddy`, `rclone/rclone`) and gets the same "update the
  checksum by hand" PR note. The Nextcloud manager matches every
  `nextcloud-X.Y.Z.tar.bz2` plus `release="X.Y.Z"`, so one PR bumps all
  five `nextcloud/` jobs. 34.0.6 is already the newest 34.x, so the first
  PR will be the 35.0.3 major.

### 2026-11-18

- **Semaphore 2.20.23 actually deploys.** Renovate #20 was merged as-is,
  even though its PR note says not to. It bumped only the release tag, so
  the bootstrap task fetched `v2.20.23/semaphore_2.19.21_darwin_arm64.tar.gz`,
  got a 404 (curl exit 56) and failed the job. The filename and sha256 are
  now 2.20.23's, and the checksum matches upstream's
  `semaphore_2.20.23_checksums.txt`. 2.20 never started against the
  database, so 2.20.23 is still a clean upgrade from 2.19.21. This also
  overrides the earlier note below to wait on 2.20.
- **New test: a release URL's filename must carry its tag's version.**
  `test_release_download_filename_matches_tag` fails a tag-only bump like
  #20 in CI, so it can't be merged by accident again.
- **Renovate's custom managers now match the job specs.** Renovate 41+
  treats a `managerFilePatterns` entry as a glob unless it's wrapped in
  `/.../`, so `"\\.nomad\\.hcl$"` matched nothing: the Dependency
  Dashboard listed only GitHub Actions and Terraform, and no image or
  release-tarball bump was ever raised. All five managers now use
  `"/\\.nomad\\.hcl$/"`.
- **App upgrades.** Every checksum was recomputed from the downloaded
  release and matched the one upstream publishes (Nextcloud, rclone, Caddy,
  Keycloak).
  - Nextcloud 34.0.4 → 34.0.6 (all five jobs). 35.x is a major upgrade and
    is left for its own change.
  - Caddy 2.11.4 → 2.11.9 and rclone 1.75.2 → 1.76.0.
  - Keycloak 26.7.5 → 26.8.2. Nothing in the 26.8 upgrading notes applies
    here: no custom login theme, no `multi-site` feature.
  - slskd 0.24.1 → 0.26.2. 0.25 moved the `global`/`groups`/`integration`
    keys and 0.26 moved `permissions.file.mode`; the live `slskd.yml` sets
    none of them.
  - Semaphore 2.19.12 → 2.19.21, the latest patch on 2.19. 2.20.23 is the
    first stable 2.20 (released 2026-11-10); since Semaphore deploys
    everything else, the minor bump waits until it has had more time out.
  - Lidarr 3.1.6.5078 → 3.2.1.5196 (develop channel, as before).
  - Dispatcharr 0.33.0 → 0.34.1 and Seerr 3.5.1 → 3.5.2 (three security
    fixes).
- **`slskd`/`sabnzbd`: `ensure-backup-bucket` is idempotent again.**
  `weed shell` now exits 1 when `s3.bucket.create` hits an existing bucket,
  which failed the prestart task on every start after the first. The script
  treats "already exists" as success and still fails on any other error.

### 2026-11-17

- **`orion` replaces `betelgeuse` in the cosmonautical datacenter.** orion
  is a new Mac mini that takes over betelgeuse's Consul/Nomad server seat.
  betelgeuse moves to the jellify datacenter as a client-only host.
  - `dispatcharr` and `lidarr` are now pinned to orion instead of
    betelgeuse. Their local state (`~/dispatcharr-local/data`,
    `~/lidarr-local/config`) has to be copied over with the jobs stopped.
  - `seaweedfs`'s `-peers`/`-mserver` and `seaweedfs-filer`'s `-master` now
    list orion instead of betelgeuse. betelgeuse's 35 volumes were evacuated
    to orion first (`volumeServer.evacuate -target`), so each keeps its other
    replica on cassiopeia or taurus. orion's master can only start once it's
    in its own `-peers`; Raft membership is fixed up after the apply with
    `cluster.raft.add`/`cluster.raft.remove`.
  - `audiomuse-ai` is now pinned to orion. It was only ever on taurus
    because that was the one host with the `.app` and its local state, not
    because of a constraint.
  - `guacamole` gains an `orion` VNC connection; betelgeuse's stays, since
    the Mac is still on the LAN at the same address.

## traefik

### 2026-10-13

- **Added a dedicated `accessLog` for fail2ban.** Only 403/404/418/999
  responses are logged, to a fixed host-local path
  (`/opt/homebrew/var/log/traefik/access.log`) rather than anywhere under
  `NOMAD_ALLOC_DIR`, so it survives this job migrating between hosts. Pairs
  with a new `traefik-abuse` fail2ban jail (8 hits / 10 min ban) — the
  jail/filter config and the `pf` anchor it needs are provisioned host-side
  via Nomadintosh, not tracked in this repo. See `traefik/README.md`.

## repo-wide

### 2026-10-05

- **SSO buttons now say "Sign in with Cosmonautical."** Semaphore's
  `display_name` changed from "Sign in with Keycloak". RomM's
  `OIDC_PROVIDER` Nomad Variable changed from `keycloak` to `Cosmonautical`;
  RomM hardcodes the "Login with" verb, so it reads "Login with
  Cosmonautical". The convention is documented in `.agents/AGENTS.md`'s "SSO
  button label".

### 2026-10-02

- **Collapsed the five Nextcloud jobs into one `nextcloud/` stack folder**
  (`nextcloud/<job-id>.nomad.hcl`) instead of five sibling directories at
  the repo root, and merged their five READMEs into one
  `nextcloud/README.md`. `main.tf`'s resource labels are unchanged — only
  the `file()` paths moved, and the jobspec contents are byte-identical, so
  `plan` should be a no-op. `tests/test_conventions.py` now tolerates
  several job specs sharing one directory/README.
- **Same collapse for `postgres/`** (`postgres` + `postgres-backup`) **and
  `seaweedfs/`** (`seaweedfs` + `seaweedfs-filer` + `seaweedfs-nfs-backup`)
  — documented together in the root README's new "Stack folders" section.
  Also reworded `seaweedfs-nfs-backup`'s stale "job ID doesn't match its
  directory/file name" note: they do match; the rename was from the legacy
  repo's `seaweedfs-backup.nomad.ncl`.

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

## home-assistant

### 2026-11-23

- **Version bumps before first deploy:** Home Assistant 2026.9.4 →
  2026.11.2, Node-RED 5.0.7 → 5.0.10, zigbee2mqtt 2.14.2 → 2.14.3 (still
  supports Node 24), Mosquitto 2.0.22 → 2.0.23,
  `node-red-contrib-home-assistant-websocket` 0.81.0 → 0.83.0. The
  2026.10/2026.11 breaking changes don't touch this job. It doesn't use the
  removed legacy mode of the `homeassistant` auth provider, and it has no
  YAML-defined MQTT entities. Mosquitto stays on 2.0.x for now; 2.1 is a
  separate bump.
- **Mosquitto memory 64 → 256 MB.** Apple `container` refuses VMs under
  200 MiB, so it would have failed its first start, the same way guacd did.
  The memory-floor convention test caught it after the rebase.

### 2026-10-05

- **New job: Home Assistant, Node-RED, Mosquitto and zigbee2mqtt.** These
  run as three groups in one job, so they deploy together but can be
  scheduled on separate nodes. Startup order is enforced with `wait-for-*`
  prestarts that poll Consul health, because Nomad has no cross-group
  dependency ordering.
- **zigbee2mqtt runs under `raw_exec`, not a container.** Apple's
  `container` VMs have no USB passthrough. It's pinned to `iot` hosts that
  publish `meta.zigbee_adapter`/`zigbee_adapter_type`, and uses Homebrew
  `node@24` because Homebrew's unversioned `node` (26.5) is past
  zigbee2mqtt 2.14's supported range (<=26.2).
- **Config files go onto NFS from raw_exec prestarts.** The container
  driver doesn't mount Nomad's `/local`, `/secrets` or `/alloc` into the
  VM (checked with `container inspect` on romm), so container tasks only
  receive env vars. Mosquitto's password file is built inside the container
  from env.
- **Home Assistant LDAP login is a `command_line` provider using vendored
  `ldap3`.** The 2026.9.4 image has no `ldapsearch`, its curl is built
  without LDAP, and `ldap3` isn't installed. That was checked by running
  the image.
- **Node-RED SSO requires `Admins` in the ID token's `groups` claim.** The
  check needs the raw ID token, so the `verify` callback takes five
  arguments: `passport-openidconnect` chooses what to pass by the callback's
  arity, and Node-RED 5 keeps that arity when it wraps `verify`.

## romm

### 2026-09-30

- **New job.** [RomM](https://github.com/rommapp/romm) — self-hosted ROM
  library manager, `container` driver, Keycloak OIDC SSO
  (`roms.cosmonautical.cloud`). Originally scoped as SQLite + Litestream
  (matching `slskd`/`sabnzbd`'s pattern), but RomM dropped SQLite support in
  3.0+ (MariaDB/MySQL/PostgreSQL only) — so it runs `ROMM_DB_DRIVER=postgresql`
  against the shared `postgres` cluster instead, same as `guacamole`/`seerr`,
  with no Litestream involved and no new backing service. ROM library mount
  is read-only (`/Volumes/ROMs`, the same NFS library `nextcloud-roms-scan`
  indexes into Nextcloud) so RomM can't become a second writer into it.

- **First deploy failed placement, then crash-looped, for two unrelated
  reasons** — both found live on `betelgeuse` right after the first push:
  1. *Placement*: the job's combined `cpu` ask (schema-init `1` + romm `2`
     = `3`) was enough to exhaust free CPU on all three cosmonautical hosts
     at once — the same class of incident as `guacamole`'s (see "macOS CPU
     fingerprint" in `.agents/AGENTS.md`). Resolved once `dispatcharr`'s own
     `cpu` was lowered, freeing enough on `betelgeuse` for Nomad's blocked-eval
     retry to place it.
  2. *Crash loop*: RomM 5.x no longer auto-detects a `{platform}/roms/{game}`
     + `{platform}/bios` layout (our library's actual structure) — without an
     explicit `config.yml` declaring it, `config_manager` logs a `CRITICAL`
     and the startup script exits 0, which looks like a plain crash loop from
     Nomad's side (no error visible in `container logs` unless you catch a
     still-running instance mid-startup — diagnosed via `container run`
     against the same image/volumes by hand on `betelgeuse`). Fixed with an
     `ensure-config` idempotent prestart task, same pattern as `slskd`/
     `sabnzbd`'s `ensure-backup-bucket`.
  3. Once past both: a gunicorn worker got OOM-killed at the job's original
     `memory = 768` (default `WEB_SERVER_CONCURRENCY=4` means 4 gunicorn
     workers plus nginx, the RQ worker/scan-worker, and the cron scheduler
     all as separate Python processes). Fixed by bumping to `memory = 1536`
     (betelgeuse had ~2.7 GB free at the time) and setting
     `WEB_SERVER_CONCURRENCY=2` — plenty for single-tenant use, and keeps
     the footprint down regardless.

- **Library mount flipped from `:ro` to `:rw`.** Adding a platform through
  RomM's UI (`ios`/`mac`/`xbox360`/`xbox`/`series-x-s`, none of which existed
  in the library yet) failed with `[Errno 30] Read-only file system` — that
  feature needs to create the platform's folder on disk. Read-only was a
  deliberate choice to keep RomM from being a second writer alongside
  `nextcloud-roms-scan`, but the UI-driven platform management was wanted
  more than that protection, so the mount is now read-write.

## slskd / sabnzbd

### 2026-09-30

- **Litestream replication for both jobs was silently broken since their
  current allocations started** (confirmed via live investigation on
  `cassiopeia`/`betelgeuse`: `litestream.stdout` logs showed thousands of
  consecutive `NoSuchBucket` errors, and the `slskd-backups`/
  `sabnzbd-backups` buckets simply didn't exist on `seaweedfs-filer` — its
  `/buckets/` listing had only the built-in `.system` entry). Root cause:
  Litestream (v0.5.17) doesn't issue `CreateBucket` itself, and these
  buckets had apparently never actually been created, going all the way
  back before today's Terraform migration — there's no prior evidence
  either job's replication ever worked. Fixed live by creating both
  buckets via `weed shell -filer=betelgeuse.cosmonautical.cloud:8888`'s
  `s3.bucket.create` (no S3 credentials needed — this goes through the
  filer's native bucket management, not the S3 gateway's auth layer);
  Litestream's pending backlog flushed through immediately
  (`sync recovered` + a real compaction in both jobs' logs within two
  minutes). Both job specs now also get an `ensure-backup-bucket` prestart
  task doing the same idempotent `s3.bucket.create` on every deploy, so
  this can't silently regress if a bucket is ever lost again — see each
  job's own README and `seaweedfs-filer`'s README.

## guacamole

### 2026-11-18

- **Port mapping fixed: `to = 8080`.** The image's Tomcat listens on 8080,
  but the driver publishes `static:to` and `to` defaults to the static
  port, so host 8084 forwarded to an empty container port and Traefik
  returned 502. The TCP check still passed, because the port forwarder
  accepts connections with nothing behind it. It's now an HTTP check.
- **guacd memory 128 → 256 MB.** The first deploy failed on every node:
  Apple `container` won't start a VM below 200 MiB ("minimum memory amount
  allowed"), and Nomad treated the driver failure as unrecoverable, so the
  alloc failed, got rescheduled and failed again. A new convention test
  catches any `container` task under the floor.
- **Deployed, Senior Cosmonauts only.** Back in `main.tf` (and out of
  `test_conventions.py`'s exemption list). Free capacity was checked first:
  each cosmonautical node has CPU to spare, and the tightest, orion, still
  has ~2.5 GB of memory free against the job's ~1.2 GB.
- **Access is gated on the `Senior Cosmonaut` realm role**, twice: a new
  Keycloak `guacamole` client (public, implicit flow) uses the
  `browser-senior-cosmonaut` flow that already gated `semaphore`, and a
  `Senior Cosmonaut` JDBC user group gets `READ` on every connection, matched
  by name against a `groups` claim of realm roles. Before this, only violet
  had a Guacamole user row; yuri, also a Senior Cosmonaut, would have logged
  in to an empty connection list.
- **Fixed the bootstrap SQL, which had never run.** It referenced psql
  variables (`:'hash_hex'`, `:'vnc_user'`, …) inside a `DO $do$ … $do$`
  block. psql doesn't substitute variables inside dollar-quoted strings, so
  the first deploy would have failed on a syntax error at `:`. The values now
  go through `set_config()`/`current_setting()`. Verified against the real
  1.6.0 schema in a throwaway Postgres: two runs give the same 6
  connections and grants.
- **`betelgeuse` connection renamed `lovelace`.** Same Mac, same address
  (`10.10.37.193`); it became `lovelace.jellify.app` after leaving the
  cosmonautical server set.
- `EXTENSION_PRIORITY=openid` so the login page redirects straight to
  Keycloak (with JDBC also loaded, Guacamole would otherwise show its own
  login form first).

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

## postgres

### 2026-11-20

- **`shared_buffers` 128MB → 256MB**, as Nextcloud 35's admin overview
  recommends. Applied live with `PATCH /config` on Patroni's REST API
  (cluster-wide, stored in Consul), then a rolling `POST /restart`:
  replicas first, waiting for `streaming`, then the primary. Leader
  (orion) didn't change. It's also in `bootstrap.dcs` here, but that block
  only seeds a brand-new cluster; for a live one, change it in the DCS.

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
