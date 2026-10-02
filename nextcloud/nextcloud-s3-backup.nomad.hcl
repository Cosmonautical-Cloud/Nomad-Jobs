job "nextcloud-s3-backup" {
  datacenters = ["cosmonautical"]
  type        = "batch"

  periodic {
    crons            = ["0 3 * * *"]
    prohibit_overlap = true
  }

  group "backup" {
    task "backup" {
      driver = "raw_exec"

      artifact {
        source      = "https://downloads.rclone.org/v1.75.1/rclone-v1.75.1-osx-arm64.zip"
        destination = "local/"

        options {
          checksum = "sha256:c61d7a371c62bcbbe882c3423aa4b8bf63485c248dd0f692997b8f0c3f6d0c6f"
        }
      }

      template {
        data        = <<EOT
[b2]
type = s3
provider = Other
access_key_id = {{ key "s3/KEY_ID" }}
secret_access_key = {{ key "s3/APPLICATION_KEY" }}
endpoint = {{ key "s3/ENDPOINT" }}
EOT
        destination = "secrets/rclone.conf"
      }

      template {
        data        = <<EOT
#!/bin/sh
set -eu
set -o pipefail

rclone="${NOMAD_TASK_DIR}/rclone-v1.75.1-osx-arm64/rclone"
conf="${NOMAD_SECRETS_DIR}/rclone.conf"
remote="b2:cosmonautical-nextcloud-backups"
src="/Volumes/Cosmonautical/nextcloud/data"
retention_days=7

stamp=$(/bin/date -u +%Y-%m-%dT%H%M%SZ)
dest="$remote/$stamp"

if "$rclone" --config "$conf" copy "$src" "$dest" --checksum; then
  echo "backup to $dest succeeded, pruning backups older than $${retention_days}d"
  cutoff=$(/bin/date -u -v-"$${retention_days}"d +%Y-%m-%dT%H%M%SZ)

  "$rclone" --config "$conf" lsf "$remote" --dirs-only | while read -r dir; do
    name=$${dir%/}
    case "$name" in
      [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T*Z) ;;
      *) continue ;;
    esac
    older=$(printf '%s\n%s\n' "$name" "$cutoff" | sort | head -n1)
    if [ "$older" = "$name" ] && [ "$name" != "$cutoff" ]; then
      echo "deleting old backup $name"
      "$rclone" --config "$conf" purge "$remote/$name"
    fi
  done
else
  echo "backup to $dest failed, leaving existing backups untouched" >&2
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
        memory = 1024
      }
    }
  }
}
