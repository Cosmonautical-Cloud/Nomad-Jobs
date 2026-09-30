job "sabnzbd" {
  datacenters = ["cosmonautical"]
  type        = "service"

  group "sabnzbd" {
    count = 1

    ephemeral_disk {
      size    = 500
      migrate = true
      sticky  = true
    }

    network {
      port "http" { static = 8085 }
    }

    # Litestream doesn't create its destination bucket itself (confirmed
    # 2026-09-30: replication silently failed for hours with NoSuchBucket
    # errors after this job's Terraform migration re-registered it, since
    # the bucket had never actually existed on seaweedfs-filer). This makes
    # bucket creation part of every deploy instead of a one-time manual
    # step - see CHANGELOG.md.
    task "ensure-backup-bucket" {
      driver = "raw_exec"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      template {
        data        = <<EOT
#!/bin/sh
set -eu
printf 's3.bucket.create -name sabnzbd-backups\nexit\n' | /opt/homebrew/bin/weed shell -filer={{ range service "seaweedfs-filer" }}{{ .Address }}:{{ .Port }}{{ end }}
EOT
        destination = "local/ensure-bucket.sh"
        perms       = "755"
      }

      config {
        command = "${NOMAD_TASK_DIR}/ensure-bucket.sh"
      }

      resources {
        cpu    = 1
        memory = 32
      }
    }

    task "seed-data" {
      driver = "raw_exec"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      template {
        data        = <<EOT
dbs:
  - path: {{ env "NOMAD_ALLOC_DIR" }}/sabnzbd-data/admin/history1.db
    replicas:
      - type: s3
        bucket: sabnzbd-backups
        path: history1.db
        endpoint: http://{{ range service "seaweedfs-s3" }}{{ .Address }}:{{ .Port }}{{ end }}
        force-path-style: true
        access-key-id: {{ key "seaweedfs-s3/ACCESS_KEY" }}
        secret-access-key: {{ key "seaweedfs-s3/SECRET_KEY" }}
        region: us-east-1
EOT
        destination = "secrets/litestream.yml"
      }

      config {
        command = "/bin/sh"
        args = [
          "-c",
          <<-EOT
          set -eu
          data_dir="$NOMAD_ALLOC_DIR/sabnzbd-data"
          mkdir -p "$data_dir/admin"

          if [ ! -s "$data_dir/sabnzbd.ini" ] && [ -s /Volumes/Cosmonautical/sabnzbd/persistent/sabnzbd.ini ]; then
            cp -a /Volumes/Cosmonautical/sabnzbd/persistent/. "$data_dir/"
          fi

          tmp="$data_dir/admin/history1.db.litestream-restore"
          rm -f "$tmp"
          if /opt/homebrew/bin/litestream restore -if-replica-exists -config "$NOMAD_SECRETS_DIR/litestream.yml" -o "$tmp" "$data_dir/admin/history1.db" 2>/dev/null && [ -s "$tmp" ]; then
            mv "$tmp" "$data_dir/admin/history1.db"
            rm -f "$data_dir/admin/history1.db-wal" "$data_dir/admin/history1.db-shm"
          else
            rm -f "$tmp"
          fi
          EOT
        ]
      }

      resources {
        cpu    = 1
        memory = 64
      }
    }

    task "sabnzbd" {
      driver = "raw_exec"

      template {
        data        = <<EOT
dbs:
  - path: {{ env "NOMAD_ALLOC_DIR" }}/sabnzbd-data/admin/history1.db
    replicas:
      - type: s3
        bucket: sabnzbd-backups
        path: history1.db
        endpoint: http://{{ range service "seaweedfs-s3" }}{{ .Address }}:{{ .Port }}{{ end }}
        force-path-style: true
        access-key-id: {{ key "seaweedfs-s3/ACCESS_KEY" }}
        secret-access-key: {{ key "seaweedfs-s3/SECRET_KEY" }}
        region: us-east-1
EOT
        destination = "secrets/litestream.yml"
      }

      template {
        data        = <<EOT
#!/bin/sh
set -eu

data_dir="$NOMAD_ALLOC_DIR/sabnzbd-data"

/opt/homebrew/bin/litestream replicate -config "$NOMAD_SECRETS_DIR/litestream.yml" &
litestream_pid=$!

/Applications/SABnzbd.app/Contents/MacOS/SABnzbd \
  --config-file "$data_dir/sabnzbd.ini" \
  --server 0.0.0.0:8085 \
  --browser 0 &
sabnzbd_pid=$!

sync_loop() {
  while true; do
    sleep 300
    cp "$data_dir/sabnzbd.ini" /Volumes/Cosmonautical/sabnzbd/persistent/ 2>/dev/null || true
    cp "$data_dir"/admin/*.sab /Volumes/Cosmonautical/sabnzbd/persistent/admin/ 2>/dev/null || true
  done
}
sync_loop &
sync_pid=$!

cleanup() {
  kill "$sync_pid" 2>/dev/null || true
  kill "$litestream_pid" 2>/dev/null || true
  kill "$sabnzbd_pid" 2>/dev/null || true
  wait "$sabnzbd_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

wait "$sabnzbd_pid"
EOT
        destination = "local/start.sh"
        perms       = "755"
      }

      config {
        command = "${NOMAD_TASK_DIR}/start.sh"
      }

      service {
        name = "sabnzbd"
        port = "http"

        check {
          name     = "tcp"
          type     = "tcp"
          port     = "http"
          interval = "10s"
          timeout  = "2s"
        }
      }

      resources {
        cpu    = 2
        memory = 512
      }
    }
  }
}
