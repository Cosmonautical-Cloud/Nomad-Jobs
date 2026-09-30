# guacamole

**Not currently deployed.** Untested — its first real Terraform `apply`
(2026-09-30) hit a cluster-wide CPU shortage (all 3 cosmonautical hosts
exhausted trying to schedule its 3 tasks at once) and got stuck blocked/
unscheduled, so it was pulled back out of `main.tf` rather than left in a
half-working state. The job spec and this README stay here as reference;
re-add the `nomad_job.guacamole` resource to `main.tf` when it's actually
ready to test, ideally after checking cluster headroom first. See
`CHANGELOG.md` for the full incident note.

[Apache Guacamole](https://guacamole.apache.org/) (`guacamole/guacamole:1.6.0`
+ `guacamole/guacd:1.6.0`, container driver) — browser-based VNC access to
all 5 cluster Macs (`cassiopeia`, `taurus`, `betelgeuse`, `galileo`,
`hopper`), routed at `guac.cosmonautical.cloud`.

Auth is split: Keycloak OIDC (implicit flow — the `guacamole-auth-sso-openid`
extension has no client-secret/PKCE support, so the Keycloak client is
public) verifies *identity*; a JDBC/Postgres extension backed by the shared
[`postgres`](../postgres) cluster owns *authorization*. A user who
authenticates via Keycloak but has no matching `guacamole_user` row gets zero
connections. The `schema-init` prestart task is a long, idempotent SQL
bootstrap (re-run on every deploy, safe to) that creates the role/database,
loads the JDBC schema fresh from the exact image version's own `initdb.sh`,
deletes the seeded `guacadmin`/`guacadmin` local-login account (would
otherwise be a full-admin backdoor around Keycloak SSO), and ensures exactly
one Guacamole user record (violet's, `ADMINISTER` permission) with VNC
connections to all 5 Macs. See the job spec's own inline comments for the
full step-by-step — this bootstrap logic is dense enough that it's better
read in place than restated here.

## Consul KV keys

| Key | Used for |
|---|---|
| `postgres/PATRONI_SUPERUSER_PASSWORD` | Bootstrap: creating the `guacamole` role/database |
| `guacamole/DB_PASSWORD` | Postgres role password (JDBC auth/authz schema) |
| `guacamole/MACOS_VNC_USERNAME` | Shared VNC login for all 5 Mac connections |
| `guacamole/MACOS_VNC_PASSWORD` | Shared VNC login for all 5 Mac connections |

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
