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
[`nextcloud-roms-scan`](../nextcloud-roms-scan) indexes into Nextcloud —
mounted **read-only** here so RomM can't be a second, less-trusted writer
into a library Nextcloud also manages. RomM's `assets` (saves/states),
`config`, and `resources` (downloaded cover art/screenshots) volumes are
on NFS at `/Volumes/Cosmonautical/romm/{assets,config,resources}` — these
three directories need to exist on the NAS before first deploy (same
manual-pre-creation expectation as other jobs' NFS-backed paths here).

**Live emulation, not server-side**: RomM's in-browser play (EmulatorJS)
runs the emulator core as WebAssembly in the user's browser - this job's
server only ever serves ROM file bytes over HTTP plus small save-state
syncs, never runs emulation itself, so its `resources` block doesn't budget
for anything like Jellyfin's transcode load. (RomM 5.1+ also has an
opt-in *server-side* "emulator streaming" mode - a genuinely different,
much heavier feature running real emulator binaries in a separate
container - not used here.)

IGDB/ScreenScraper/SteamGridDB/RetroAchievements metadata-provider
credentials aren't wired up - RomM works without them, just without
scraped metadata/box art. Add `IGDB_CLIENT_ID`/`IGDB_CLIENT_SECRET`/etc. to
the `romm.env` template and a matching Consul KV entry if scraping is
wanted later.

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

## Nomad Variables (non-sensitive)

Path `nomad/jobs/romm`, populated via the HTTP API (no `nomad` CLI on any
host, same as Consul KV):

```sh
curl -X PUT 127.0.0.1:4646/v1/var/nomad/jobs/romm -d '{
  "Items": {
    "ROMM_BASE_URL": "https://roms.cosmonautical.cloud",
    "OIDC_PROVIDER": "keycloak",
    "OIDC_REDIRECT_URI": "https://roms.cosmonautical.cloud/api/oauth/openid",
    "OIDC_SERVER_APPLICATION_URL": "https://auth.cosmonautical.cloud/realms/cosmonautical"
  }
}'
```

| Item | Used for |
|---|---|
| `ROMM_BASE_URL` | Public URL of this instance |
| `OIDC_PROVIDER` | Label RomM shows for the SSO login option |
| `OIDC_REDIRECT_URI` | Must match the redirect URI registered on the Keycloak client |
| `OIDC_SERVER_APPLICATION_URL` | Keycloak realm issuer URL |

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
