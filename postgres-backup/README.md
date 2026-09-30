# postgres-backup

Periodic batch job (`0 */6 * * *`) that runs `pg_dumpall` against the
current Postgres leader (discovered via the `postgres` Consul service, so it
always finds the writer even after a failover) and writes a gzip-compressed,
timestamped dump to `/Volumes/Cosmonautical/postgres-backups`. Prunes dumps
older than 14 days, but only after a successful dump — a failed
`pg_dumpall` leaves existing backups untouched rather than pruning first.

Waits (polling every 10s, up to 60 attempts) for `pg_isready` against the
discovered host before dumping, since the leader can briefly be unavailable
during a Patroni failover.

Backs up the whole cluster (`pg_dumpall`, not a per-database `pg_dump`) since
every app sharing the [`postgres`](../postgres) cluster (`nextcloud`,
`open-webui`, more to come) needs to be restorable together.

For history/rationale, see [`CHANGELOG.md`](../CHANGELOG.md).
