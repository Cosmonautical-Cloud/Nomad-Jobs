# semaphore

The [SemaphoreUI](https://semaphoreui.com/) server itself — `semaphore.cosmonautical.cloud`
— **this is what will eventually run this very repo's `plan`/`apply`** once
it's wired in (see root README's "Wiring into Semaphore"). Meta note: until
this job is `terraform import`ed and this repo's Semaphore App is actually
configured, changes here still have to be applied by hand.

Elaborate idempotent `bootstrap` prestart task, re-run safely on every
deploy: creates its Postgres role/database on the shared
[`postgres`](../postgres) cluster, provisions a pinned Ansible venv
(`ansible==14.4.0`, outside the job's ephemeral disk so it survives
redeploys) for running Nomadable/Nomadintosh/nomaduntu playbooks, downloads
the checksum-pinned Semaphore binary itself, renders `config.json`
(Postgres + Keycloak OIDC + secrets), and provisions two admin accounts:
violet as an external (OIDC-only) admin, and a local break-glass admin
(password from Consul KV `semaphore/BOOTSTRAP_ADMIN_PASSWORD`) for if
Keycloak is ever unreachable — **note the contrast with `keycloak`'s own
hardcoded admin password**, this job does the "break-glass local admin"
pattern properly.

## Consul KV keys

| Key | Used for |
|---|---|
| `postgres/PATRONI_SUPERUSER_PASSWORD` | Bootstrap: creating the `semaphore` role/database |
| `semaphore/DB_PASSWORD` | Postgres role password |
| `semaphore/COOKIE_HASH` | Session cookie signing |
| `semaphore/COOKIE_ENCRYPTION` | Session cookie encryption |
| `semaphore/ACCESS_KEY_ENCRYPTION` | At-rest encryption for stored playbook access keys |
| `semaphore/OIDC_CLIENT_SECRET` | Keycloak OIDC client secret |
| `semaphore/BOOTSTRAP_ADMIN_PASSWORD` | Local break-glass admin password |

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
