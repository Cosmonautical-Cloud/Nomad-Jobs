# keycloak

The cluster's SSO/IdP (`auth.cosmonautical.cloud`), Keycloak `26.7.3`
(artifact-downloaded tarball, checksum-pinned), running on OpenJDK via
`raw_exec`. Backed by its own database on the shared
[`postgres`](../postgres) cluster (`KC_DB_URL` points at
`postgres.service.consul` directly, same static-DNS pattern as
`dispatcharr`, not the `{{ range service ... }}` template pattern).

Consumed by [`guacamole`](../guacamole), [`open-webui`](../open-webui),
[`semaphore`](../semaphore), and (indirectly, via [`openldap`](../openldap))
Nextcloud's identity backend — this is load-bearing infra for most of the
apps in this cluster that need auth.

**Fixed during migration, 2026-09-30** (the one deliberate deviation from
"migrate unmodified" in this repo): the legacy spec had
`KEYCLOAK_ADMIN_PASSWORD = "changeme"` hardcoded in plaintext — the only
literal secret found anywhere in this repo, and this repo is public. Wired
to the pre-existing Consul KV key `keycloak/BOOTSTRAP_ADMIN_PASSWORD` via
`template` instead, same pattern as `KC_DB_PASSWORD` right above it and
`semaphore`'s break-glass-admin password. See `CHANGELOG.md` and
`.agents/AGENTS.md`'s "This repo is public" section.

## Consul KV keys

| Key | Used for |
|---|---|
| `keycloak/BOOTSTRAP_ADMIN_PASSWORD` | Initial admin user password |
| `keycloak/DB_PASSWORD` | Postgres role password |

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
