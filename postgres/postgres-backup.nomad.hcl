job "postgres-backup" {
  datacenters = ["cosmonautical"]
  type        = "batch"

  periodic {
    crons            = ["0 */6 * * *"]
    prohibit_overlap = true
  }

  group "backup" {
    task "postgres-backup" {
      driver = "raw_exec"

      env {
        LC_ALL = "en_US.UTF-8"
      }

      template {
        data        = <<EOT
PGPASSWORD={{ key "postgres/PATRONI_SUPERUSER_PASSWORD" }}
EOT
        destination = "secrets/postgres-backup.env"
        env         = true
      }

      template {
        data        = <<EOT
#!/bin/sh
set -eu
set -o pipefail

dest=/Volumes/Cosmonautical/postgres-backups
retention_days=14
pg_bin=/opt/homebrew/opt/postgresql@18/bin

host=""
attempts=0
until [ -n "$host" ] && "$pg_bin/pg_isready" -h "$host" -p 5432 -d postgres -U violet >/dev/null 2>&1; do
  attempts=$((attempts + 1))
  if [ "$attempts" -ge 60 ]; then
    echo "postgres never became ready, giving up" >&2
    exit 1
  fi
  /bin/sleep 10
  host="{{ range service "postgres" }}{{ .Address }}{{ end }}"
done

stamp=$(/bin/date +%Y-%m-%dT%H%M%S)
tmp="$dest/.pg_dumpall-$stamp.sql.gz.tmp"
out="$dest/pg_dumpall-$stamp.sql.gz"

if "$pg_bin/pg_dumpall" -h "$host" -p 5432 -U violet | /usr/bin/gzip > "$tmp"; then
  /bin/mv "$tmp" "$out"
  /usr/bin/find "$dest" -name 'pg_dumpall-*.sql.gz' -mtime "+$retention_days" -delete
else
  echo "pg_dumpall failed, leaving previous backups in place" >&2
  /bin/rm -f "$tmp"
  exit 1
fi
EOT
        destination = "local/backup.sh"
        perms       = "755"
      }

      config {
        command = "${NOMAD_TASK_DIR}/backup.sh"
      }

      resources {
        cpu    = 1
        memory = 256
      }
    }
  }
}
