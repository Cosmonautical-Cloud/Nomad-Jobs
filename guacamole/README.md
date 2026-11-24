# guacamole

[Apache Guacamole](https://guacamole.apache.org/) (`guacamole/guacamole:1.6.0`
+ `guacamole/guacd:1.6.0`, container driver) — browser-based VNC access to
the cluster Macs (`cassiopeia`, `taurus`, `orion`, `lovelace`, `galileo`,
`hopper`, `hubble`), routed at `guac.cosmonautical.cloud`. **Senior Cosmonauts only.**

First deployed 2026-11-18. An earlier attempt on 2026-09-30 got stuck
unscheduled and was pulled from `main.tf`; see `CHANGELOG.md`.

## Access

Two layers, both keyed on the Keycloak realm role **`Senior Cosmonaut`**
(granted through the `Admins` group):

1. **Keycloak** — the `guacamole` client's browser flow is overridden to
   `browser-senior-cosmonaut`, which runs the realm's normal login (password
   + conditional OTP) and then denies anyone without the role. The same flow
   gates `semaphore`. The client also has *Consent required* on, so after a
   Senior Cosmonaut's first login Guacamole stays listed in their account
   console's Applications page. *Always display in UI* is off on purpose:
   it can't be filtered by role and would show the link to everyone.
2. **Guacamole** — a `realm roles as groups` protocol mapper on the Keycloak
   client puts the user's realm roles in the ID token's `groups` claim
   (`OPENID_GROUPS_CLAIM_TYPE`). The JDBC database has a `Senior Cosmonaut`
   user group with `READ` on every connection, and Guacamole applies
   database group permissions to SSO users whose groups match by name. So a
   Senior Cosmonaut gets every connection without needing their own
   `guacamole_user` row.

Keycloak's client config isn't managed by this repo; it was set up by hand
through the admin API.

## Notable pieces

- **SSO only.** Keycloak OIDC (implicit flow — `guacamole-auth-sso-openid`
  has no client-secret/PKCE support, so the Keycloak client is public)
  verifies identity; the JDBC/Postgres extension on the shared
  [`postgres`](../postgres) cluster owns authorization.
  `EXTENSION_PRIORITY=openid` makes the login page redirect straight to
  Keycloak instead of showing the JDBC username/password form.
- **`schema-init` prestart task** — idempotent, re-run on every deploy:
  1. Creates the `guacamole` Postgres role/database if missing.
  2. Loads the JDBC schema if missing, generated from the exact image
     version via its own `initdb.sh` (not a hand-copied SQL file).
  3. Deletes the schema's seeded `guacadmin`/`guacadmin` account, which
     would otherwise be a full-admin backdoor around Keycloak.
  4. Ensures violet's user row (random, never-checked password) with
     `ADMINISTER`, and the `Senior Cosmonaut` user group.
  5. Ensures a VNC connection (macOS Screen Sharing, port 5900) per Mac,
     with parameters synced from Consul KV on every run, and `READ` for
     violet and the group.
- **psql variables don't expand inside `DO $do$ … $do$`.** The bootstrap
  hands them to the PL/pgSQL block with `set_config('bootstrap.*', …)` /
  `current_setting('bootstrap.*')` instead.
- **Connections are only ever added or updated, never removed.** Dropping a
  Mac from the list leaves its connection in the database; delete it in
  Guacamole's admin UI.

## Consul KV keys

| Key | Used for |
|---|---|
| `postgres/PATRONI_SUPERUSER_PASSWORD` | Bootstrap: creating the `guacamole` role/database |
| `guacamole/DB_PASSWORD` | Postgres role password (JDBC auth/authz schema) |
| `guacamole/MACOS_VNC_USERNAME` | Shared VNC login for all the Mac connections |
| `guacamole/MACOS_VNC_PASSWORD` | Shared VNC login for all the Mac connections |

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
