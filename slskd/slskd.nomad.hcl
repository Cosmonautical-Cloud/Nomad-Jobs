job "slskd" {
  datacenters = ["cosmonautical"]
  type        = "service"

  group "slskd" {
    count = 1

    ephemeral_disk {
      size    = 2500
      migrate = true
      sticky  = true
    }

    network {
      port "http" { static = 5030 }
      port "https" { static = 5031 }
      port "soulseek" { static = 50300 }
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
printf 's3.bucket.create -name slskd-backups\nexit\n' | /opt/homebrew/bin/weed shell -filer={{ range service "seaweedfs-filer" }}{{ .Address }}:{{ .Port }}{{ end }}
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

    task "update-port-forward" {
      driver = "raw_exec"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      template {
        data        = <<EOT
#!/bin/sh
set -eu

unifi_host="https://10.10.37.1"
rule_id="6712612ec4f920377405e999"
cookie_jar="$NOMAD_SECRETS_DIR/unifi-cookies.txt"

login_headers=$(curl -sk -c "$cookie_jar" -D - -o /dev/null -X POST "$unifi_host/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"nomad","password":"{{ key "unifi/NOMAD_USER_PASSWORD" }}"}')

csrf=$(echo "$login_headers" | grep -i "^x-csrf-token" | tail -1 | awk '{print $2}' | tr -d '\r')

current_rule=$(curl -sk -b "$cookie_jar" -H "X-CSRF-Token: $csrf" \
  "$unifi_host/proxy/network/api/s/default/rest/portforward/$rule_id")

updated_rule=$(echo "$current_rule" | python3 -c "
import json, sys
d = json.load(sys.stdin)
rule = d['data'][0]
rule['fwd'] = '$NOMAD_IP_soulseek'
print(json.dumps(rule))
")

curl -sk -b "$cookie_jar" -H "X-CSRF-Token: $csrf" -H "Content-Type: application/json" \
  -X PUT "$unifi_host/proxy/network/api/s/default/rest/portforward/$rule_id" \
  -d "$updated_rule" -o /dev/null -w "port-forward update: %%{http_code}\n"

rm -f "$cookie_jar"
EOT
        destination = "secrets/update-port-forward.sh"
        perms       = "755"
      }

      config {
        command = "${NOMAD_SECRETS_DIR}/update-port-forward.sh"
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

      env {
        HOME = "/Users/violet"
      }

      template {
        data        = <<EOT
dbs:
  - path: {{ env "NOMAD_ALLOC_DIR" }}/slskd-data/data/transfers.db
    replicas:
      - type: s3
        bucket: slskd-backups
        path: transfers.db
        endpoint: http://{{ range service "seaweedfs-s3" }}{{ .Address }}:{{ .Port }}{{ end }}
        force-path-style: true
        access-key-id: {{ key "seaweedfs-s3/ACCESS_KEY" }}
        secret-access-key: {{ key "seaweedfs-s3/SECRET_KEY" }}
        region: us-east-1
  - path: {{ env "NOMAD_ALLOC_DIR" }}/slskd-data/data/events.db
    replicas:
      - type: s3
        bucket: slskd-backups
        path: events.db
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
          data_dir="$NOMAD_ALLOC_DIR/slskd-data"
          mkdir -p "$data_dir/data"

          if [ ! -s "$data_dir/slskd.yml" ] && [ -s /Volumes/Cosmonautical/slskd/persistent/slskd.yml ]; then
            cp /Volumes/Cosmonautical/slskd/persistent/slskd.yml "$data_dir/"
            cp /Volumes/Cosmonautical/slskd/persistent/data/browse.cache "$data_dir/data/" 2>/dev/null || true
            cp /Volumes/Cosmonautical/slskd/persistent/data/messaging.db "$data_dir/data/" 2>/dev/null || true
            cp /Volumes/Cosmonautical/slskd/persistent/data/search.db "$data_dir/data/" 2>/dev/null || true
            cp /Volumes/Cosmonautical/slskd/persistent/data/shares.local.bak.db "$data_dir/data/" 2>/dev/null || true
          fi

          for db in transfers.db events.db; do
            tmp="$data_dir/data/$db.litestream-restore"
            rm -f "$tmp"
            if /opt/homebrew/bin/litestream restore -if-replica-exists -config "$NOMAD_SECRETS_DIR/litestream.yml" -o "$tmp" "$data_dir/data/$db" 2>/dev/null && [ -s "$tmp" ]; then
              mv "$tmp" "$data_dir/data/$db"
              rm -f "$data_dir/data/$db-wal" "$data_dir/data/$db-shm"
            else
              rm -f "$tmp"
              if [ ! -s "$data_dir/data/$db" ] && [ -s "/Volumes/Cosmonautical/slskd/persistent/data/$db" ]; then
                cp "/Volumes/Cosmonautical/slskd/persistent/data/$db" "$data_dir/data/"
              fi
            fi
          done
          EOT
        ]
      }

      resources {
        cpu    = 1
        memory = 64
      }
    }

    task "litestream" {
      driver = "raw_exec"

      template {
        data        = <<EOT
dbs:
  - path: {{ env "NOMAD_ALLOC_DIR" }}/slskd-data/data/transfers.db
    replicas:
      - type: s3
        bucket: slskd-backups
        path: transfers.db
        endpoint: http://{{ range service "seaweedfs-s3" }}{{ .Address }}:{{ .Port }}{{ end }}
        force-path-style: true
        access-key-id: {{ key "seaweedfs-s3/ACCESS_KEY" }}
        secret-access-key: {{ key "seaweedfs-s3/SECRET_KEY" }}
        region: us-east-1
  - path: {{ env "NOMAD_ALLOC_DIR" }}/slskd-data/data/events.db
    replicas:
      - type: s3
        bucket: slskd-backups
        path: events.db
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
          until [ -s "$NOMAD_ALLOC_DIR/slskd-data/data/transfers.db" ] && [ -s "$NOMAD_ALLOC_DIR/slskd-data/data/events.db" ]; do
            sleep 2
          done
          exec /opt/homebrew/bin/litestream replicate -config "$NOMAD_SECRETS_DIR/litestream.yml"
          EOT
        ]
      }

      resources {
        cpu    = 1
        memory = 256
      }
    }

    task "slskd" {
      driver = "raw_exec"

      artifact {
        source      = "https://github.com/slskd/slskd/releases/download/0.24.1/slskd-0.24.1-osx-arm64.zip"
        destination = "local/slskd-release"
        mode        = "dir"

        options {
          checksum = "sha256:03604ef2359564f806372d0874716551bfa81a2f29b759556c76993aead91b2e"
        }
      }

      template {
        data        = <<EOT
#!/bin/sh
set -eu

data_dir="$NOMAD_ALLOC_DIR/slskd-data"

chmod +x "$NOMAD_TASK_DIR/slskd-release/slskd"
"$NOMAD_TASK_DIR/slskd-release/slskd" -a "$data_dir" -c "$data_dir/slskd.yml" &
slskd_pid=$!

sync_loop() {
  while true; do
    sleep 300
    cp "$data_dir/slskd.yml" /Volumes/Cosmonautical/slskd/persistent/ 2>/dev/null || true
    cp "$data_dir/data/browse.cache" /Volumes/Cosmonautical/slskd/persistent/data/ 2>/dev/null || true
    cp "$data_dir/data/messaging.db" /Volumes/Cosmonautical/slskd/persistent/data/ 2>/dev/null || true
    cp "$data_dir/data/search.db" /Volumes/Cosmonautical/slskd/persistent/data/ 2>/dev/null || true
    cp "$data_dir/data/shares.local.bak.db" /Volumes/Cosmonautical/slskd/persistent/data/ 2>/dev/null || true
  done
}
sync_loop &
sync_pid=$!

cleanup() {
  kill "$sync_pid" 2>/dev/null || true
  kill "$slskd_pid" 2>/dev/null || true
  wait "$slskd_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

wait "$slskd_pid"
EOT
        destination = "local/start.sh"
        perms       = "755"
      }

      config {
        command = "${NOMAD_TASK_DIR}/start.sh"
      }

      service {
        name = "slskd"
        port = "http"
      }

      resources {
        cpu    = 2
        memory = 512
      }
    }
  }
}
