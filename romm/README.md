# romm

Runs [RomM](https://github.com/rommapp/romm) (`rommapp/romm:5.3.1`,
`container` driver) — a self-hosted ROM library manager with metadata
scraping, box art, and in-browser play (EmulatorJS; emulation runs
client-side in the browser, not on this job's server) — routed at
`roms.cosmonautical.cloud`.

RomM dropped SQLite support in 3.0+ (MariaDB/MySQL/PostgreSQL only now), so
unlike the original plan this isn't Litestream-backed — it runs
`ROMM_DB_DRIVER=postgresql` against the shared [`postgres`](../postgres)
cluster instead, same pattern as [`guacamole`](../guacamole)/[`seerr`](../seerr),
with no new backing service to stand up or separately back up. It also
needs Redis, filled by the shared [`redis`](../redis) cluster.

Auth is Keycloak OIDC (confidential client, authorization code flow) —
unlike `guacamole`'s OpenID extension, RomM supports a client secret
directly, so no public/implicit-flow workaround is needed. RomM creates its
own user record automatically on first Keycloak login
(`OIDC_ALLOW_REGISTRATION` defaults `true`), so unlike `guacamole` there's
no separate authorization-bootstrap step.

The `schema-init` prestart task is a short, idempotent bootstrap
(re-run on every deploy, safe to) that creates the `romm` Postgres
role/database if missing — RomM runs its own Alembic migrations against it
on container start, so no schema-loading step is needed the way
`guacamole`'s JDBC extension needs one.

The ROM library mount (`/Volumes/ROMs`) is the same NFS-backed library
[`nextcloud-roms-scan`](../nextcloud) indexes into Nextcloud.
Originally mounted read-only so RomM couldn't be a second, less-trusted
writer into a library Nextcloud also manages — flipped to **read-write**
2026-09-30 (see `CHANGELOG.md`) once RomM's own "add platform" UI was
actually wanted, since that feature needs to create the platform's folder
on disk (`POST`ing a new platform without write access fails with
`[Errno 30] Read-only file system`). RomM is now a second writer into this
library alongside Nextcloud — worth keeping in mind if the two ever fight
over the same file, though in practice RomM only creates platform folders
and writes files a user explicitly uploads/renames through its own UI.
RomM's `assets` (saves/states),
`config`, and `resources` (downloaded cover art/screenshots) volumes are
on NFS at `/Volumes/Cosmonautical/romm/{assets,config,resources}` — these
three directories need to exist on the NAS before first deploy (same
manual-pre-creation expectation as other jobs' NFS-backed paths here).

**`config/config.yml` needs real content, not just the empty file RomM
creates on its own.** RomM 5.x no longer auto-detects a `{platform}/roms/{game}`
+ `{platform}/bios` layout (our library's actual structure, see
[`/Volumes/ROMs/README.md`](https://roms.cosmonautical.cloud) on the NFS
share) — without an explicit declaration it logs a `CRITICAL` from
`config_manager` and the startup script exits, which looks from the Nomad
side like a plain crash loop (exit 0, no error visible in `container logs`
unless you catch a still-running instance and read past "Running database
migrations"). Found 2026-09-30 (see `CHANGELOG.md`) — fixed the same way as
`slskd`/`sabnzbd`'s `ensure-backup-bucket`: an idempotent `ensure-config`
prestart task (re-run on every deploy) writes it straight onto the
NFS-backed `config/` volume, not into the container's own `/local`:

```yaml
filesystem:
  structure:
    default: "{platform}/roms/{game}"
    firmware: "{platform}/bios"
```

Self-healing on every redeploy — if `config/` is ever wiped, the next deploy
recreates this file before the `romm` task starts.

**Live emulation, not server-side**: RomM's in-browser play (EmulatorJS)
runs the emulator core as WebAssembly in the user's browser - this job's
server only ever serves ROM file bytes over HTTP plus small save-state
syncs, never runs emulation itself, so its `resources` block doesn't budget
for anything like Jellyfin's transcode load. (RomM 5.1+ also has an
opt-in *server-side* "emulator streaming" mode - a genuinely different,
much heavier feature running real emulator binaries in a separate
container - not used here.)

IGDB, SteamGridDB, and RetroAchievements metadata-provider credentials are
wired up via a dedicated `secrets/romm-metadata.env` template (separate
from `secrets/romm.env` so the optional, may-not-exist-yet keys stay
visibly distinct from the required ones). Each uses `keyOrDefault ... ""`
rather than `key`, so the job still deploys/renders cleanly before a given
key is actually populated in Consul KV - RomM treats an empty value the
same as the variable being unset (that provider's scraping just stays
disabled). ScreenScraper (`SCREENSCRAPER_USER`/`SCREENSCRAPER_PASSWORD`)
and the no-key flag providers (Hasheous/LaunchBox/PlayMatch/Flashpoint/HLTB)
aren't wired up yet - same pattern to extend if wanted later.

This is also the first job here storing its non-sensitive config in a
[Nomad Variable](https://developer.hashicorp.com/nomad/docs/job-declare/nomad-variables)
rather than hardcoding it into the `.nomad.hcl` file — see "Nomad Variables"
below and `../.agents/AGENTS.md`'s "Non-secret config (Nomad Variables)"
section for the convention this establishes going forward.

## Consul KV keys (sensitive)

| Key | Used for |
|---|---|
| `postgres/PATRONI_SUPERUSER_PASSWORD` | Bootstrap: creating the `romm` role/database |
| `romm/DB_PASSWORD` | Postgres role password |
| `romm/AUTH_SECRET_KEY` | `ROMM_AUTH_SECRET_KEY` - generate with `openssl rand -hex 32` |
| `romm/OIDC_CLIENT_SECRET` | Keycloak confidential client secret |
| `redis/PASSWORD` | Shared Redis cluster auth |
| `romm/IGDB_CLIENT_ID` | `IGDB_CLIENT_ID` - Twitch Developer Portal, register an app (optional, empty disables IGDB scraping) |
| `romm/IGDB_CLIENT_SECRET` | `IGDB_CLIENT_SECRET` - same Twitch app (optional) |
| `romm/STEAMGRIDDB_API_KEY` | `STEAMGRIDDB_API_KEY` - SteamGridDB preferences/API tab (optional, box art only) |
| `romm/RETROACHIEVEMENTS_API_KEY` | `RETROACHIEVEMENTS_API_KEY` - RA account settings (optional) |

## Nomad Variables (non-sensitive)

Path `nomad/jobs/romm`, populated via the HTTP API (no `nomad` CLI on any
host, same as Consul KV):

```sh
curl -X PUT 127.0.0.1:4646/v1/var/nomad/jobs/romm -d '{
  "Items": {
    "ROMM_BASE_URL": "https://roms.cosmonautical.cloud",
    "OIDC_PROVIDER": "Cosmonautical",
    "OIDC_REDIRECT_URI": "https://roms.cosmonautical.cloud/api/oauth/openid",
    "OIDC_SERVER_APPLICATION_URL": "https://auth.cosmonautical.cloud/realms/cosmonautical"
  }
}'
```

| Item | Used for |
|---|---|
| `ROMM_BASE_URL` | Public URL of this instance |
| `OIDC_PROVIDER` | Provider name on the SSO button. RomM hardcodes the verb, so `Cosmonautical` renders as "Login with Cosmonautical" (see `../.agents/AGENTS.md`'s "SSO button label") |
| `OIDC_REDIRECT_URI` | Must match the redirect URI registered on the Keycloak client |
| `OIDC_SERVER_APPLICATION_URL` | Keycloak realm issuer URL |

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
