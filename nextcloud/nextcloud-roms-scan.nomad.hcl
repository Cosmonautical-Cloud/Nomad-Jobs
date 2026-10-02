job "nextcloud-roms-scan" {
  datacenters = ["cosmonautical"]
  type        = "batch"

  periodic {
    crons            = ["0 0 * * *"]
    prohibit_overlap = true
  }

  group "roms-scan" {
    task "wait-for-mounts" {
      driver = "raw_exec"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      env {
        HOME = "/Users/violet"
      }

      config {
        command = "/bin/sh"
        args = [
          "-c",
          <<-EOT
          wait_for_mount() {
            volume_path="$1"
            attempts=0
            until /sbin/mount | /usr/bin/grep -Fq " on $volume_path (nfs"; do
              attempts=$((attempts + 1))
              if [ "$attempts" -ge 30 ]; then
                echo "$volume_path NFS mount did not appear" >&2
                exit 1
              fi
              /bin/sleep 2
            done
          }

          wait_for_mount /Volumes/Cosmonautical
          wait_for_mount /Volumes/ROMs

          until [ -s /Volumes/Cosmonautical/nextcloud/persistent/config/config.php ]; do
            echo "Waiting for the Nextcloud installation..."
            /bin/sleep 2
          done
          EOT
        ]
      }

      resources {
        cpu    = 1
        memory = 16
      }
    }

    task "roms-scan" {
      driver = "raw_exec"

      artifact {
        source      = "https://download.nextcloud.com/server/releases/nextcloud-34.0.4.tar.bz2?archive=false"
        destination = "local/nextcloud-34.0.4.tar.bz2"
        mode        = "file"

        options {
          checksum = "sha256:00f226e6364f96e0918ab06157158f66601b8cedc25af777f5ee5a3056f42b83"
        }
      }

      env {
        NEXTCLOUD_ADMIN_USER                 = "admin"
        NEXTCLOUD_APP_DIR                    = "${NOMAD_ALLOC_DIR}/data/nextcloud"
        NEXTCLOUD_DATA_DIR                   = "/Volumes/Cosmonautical/nextcloud/data"
        OBJC_DISABLE_INITIALIZE_FORK_SAFETY  = "YES"
        PATH                                 = "/opt/homebrew/opt/php@8.4/bin:/opt/homebrew/opt/php@8.4/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
        PHP_INI_SCAN_DIR                     = "/opt/homebrew/etc/php/8.4/conf.d:${NOMAD_TASK_DIR}/php-conf"
        PGGSSENCMODE = "disable"
      }

      template {
        data        = <<EOT
memory_limit = 512M
EOT
        destination = "local/php-conf/nextcloud.ini"
      }

      template {
        data        = <<EOT
POSTGRES_PASSWORD={{ key "nextcloud/DB_PASSWORD" }}
REDIS_PASSWORD={{ key "redis/PASSWORD" }}
REDIS_HOST={{ range service "redis" }}{{ .Address }}{{ end }}
REDIS_PORT={{ range service "redis" }}{{ .Port }}{{ end }}
EOT
        destination = "secrets/nextcloud.env"
        env         = true
      }

      template {
        data        = <<EOT
#!/bin/sh
set -eu

app="$NEXTCLOUD_APP_DIR"
persistent="/Volumes/Cosmonautical/nextcloud/persistent"

mkdir -p "${NOMAD_ALLOC_DIR}/data"
/usr/bin/tar -xjf "$NOMAD_TASK_DIR/nextcloud-34.0.4.tar.bz2" -C "${NOMAD_ALLOC_DIR}/data"

rm -rf "$app/config" "$app/custom_apps"
ln -s "$persistent/config" "$app/config"
ln -s "$persistent/custom_apps" "$app/custom_apps"

cd "$app"
exec /opt/homebrew/opt/php@8.4/bin/php occ files:scan --path="$NEXTCLOUD_ADMIN_USER/files/ROMs"
EOT
        destination = "local/run.sh"
        perms       = "755"
      }

      config {
        command = "${NOMAD_TASK_DIR}/run.sh"
      }

      resources {
        cpu    = 1
        memory = 512
      }
    }
  }
}
