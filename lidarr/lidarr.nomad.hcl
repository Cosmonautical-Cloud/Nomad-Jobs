job "lidarr" {
  datacenters = ["cosmonautical"]
  type        = "service"

  group "lidarr" {
    count = 1

    constraint {
      attribute = "${attr.unique.hostname}"
      value     = "betelgeuse.cosmonautical.cloud"
    }

    network {
      port "http" { static = 8686 }
    }

    task "prepare-data-dir" {
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
          set -eu
          attempts=0
          until /sbin/mount | /usr/bin/grep -Fq " on /Volumes/Cosmonautical (nfs"; do
            attempts=$((attempts + 1))
            if [ "$attempts" -ge 30 ]; then
              echo "Cosmonautical NFS mount did not appear" >&2
              exit 1
            fi
            /bin/sleep 2
          done

          data_dir="/Users/violet/lidarr-local/config"
          mkdir -p "$data_dir"
          if [ ! -s "$data_dir/config.xml" ] && [ -s /Volumes/Cosmonautical/lidarr/config/config.xml ]; then
            cp /Volumes/Cosmonautical/lidarr/config/config.xml "$data_dir/"
          fi
          EOT
        ]
      }

      resources {
        cpu    = 1
        memory = 16
      }
    }

    task "backup-db" {
      driver = "raw_exec"

      config {
        command = "/bin/sh"
        args = [
          "-c",
          <<-EOT
          mkdir -p /Volumes/Cosmonautical/lidarr/config
          while true; do
            sleep 300
            /opt/homebrew/bin/sqlite3 /Users/violet/lidarr-local/config/lidarr.db ".backup '/Volumes/Cosmonautical/lidarr/config/lidarr.db.bak'" 2>/dev/null || true
            cp /Users/violet/lidarr-local/config/config.xml /Volumes/Cosmonautical/lidarr/config/config.xml 2>/dev/null || true
          done
          EOT
        ]
      }

      resources {
        cpu    = 1
        memory = 64
      }
    }

    task "lidarr" {
      driver = "raw_exec"

      artifact {
        source      = "https://github.com/Lidarr/Lidarr/releases/download/v3.1.6.5078/Lidarr.develop.3.1.6.5078.osx-core-arm64.tar.gz"
        destination = "local/lidarr-release"
        mode        = "dir"

        options {
          checksum = "sha256:c191bf86fdf48e824724ea71be4963ea53829bead48d0c3b507f5f43ce2b555f"
        }
      }

      template {
        data        = <<EOT
#!/bin/sh
set -eu

bin="$NOMAD_TASK_DIR/lidarr-release/Lidarr/Lidarr"
chmod +x "$bin"
codesign --sign - --force "$bin"

exec "$bin" -nobrowser -data=/Users/violet/lidarr-local/config
EOT
        destination = "local/start.sh"
        perms       = "755"
      }

      config {
        command = "${NOMAD_TASK_DIR}/start.sh"
      }

      service {
        name = "lidarr"
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
        memory = 4096
      }
    }
  }
}
