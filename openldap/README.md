# openldap

**Job ID is `openldap`, not `auth`** — the legacy repo's filename
(`auth.nomad.hcl`) didn't match its own job ID, so this directory is named
after the job ID per this repo's convention (same situation as
`seaweedfs-nfs-backup`). The `auth.cosmonautical.cloud` hostname belongs to
[`keycloak`](../keycloak), not this job — this job only backs Keycloak's
(and Nextcloud's) directory lookups, it isn't reachable externally itself.

Runs OpenLDAP (`slapd`, Homebrew) on a non-standard port (`3890`, avoiding a
conflict with the system's own `389`), suffix `dc=cosmonautical,dc=cloud`.
Two ACL grants exist beyond the default read-all: `cn=keycloak,...` gets
write on `ou=users`/`ou=groups` (Keycloak owns identity), and
`cn=nextcloud,...` gets read (Nextcloud's user backend).

Persistence: a prestart task restores from an LDIF backup on
`/Volumes/Cosmonautical/openldap/persistent` if local state is empty; the
main task dumps a fresh LDIF back to the same path every 15 minutes via
`slapcat`. This is a full-dump backup, not replication — acceptable for a
single-instance directory service with infrequent writes.

## Consul KV keys

| Key | Used for |
|---|---|
| `openldap/ROOT_PASSWORD` | `rootdn` bind password |

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
