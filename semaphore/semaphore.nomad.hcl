job "semaphore" {
  datacenters = ["cosmonautical"]
  type        = "service"

  group "semaphore" {
    count = 1

    ephemeral_disk {
      size    = 500
      migrate = true
      sticky  = true
    }

    network {
      port "http" { static = 3000 }
    }

    # Idempotent bootstrap, run once before the server starts:
    #   1. creates the `semaphore` Postgres role/database on the cluster's
    #      existing Patroni cluster (postgres.nomad.hcl) - safe to re-run,
    #      skips creation if they already exist.
    #   2. creates a pinned ansible venv at a fixed host-local path (outside
    #      this job's ephemeral_disk, same shape as minecraft.nomad.hcl's
    #      fetch-jdk) - skipped once already present.
    #   3. fetches the Semaphore binary itself, checksum-pinned, into this
    #      allocation's shared alloc dir so the main task can exec it.
    #   4. renders config.json (Postgres + OIDC + secrets) into the same
    #      shared location.
    #   5. provisions violet as an external (OIDC-only) admin account, plus
    #      a local break-glass admin for if Keycloak is ever unreachable -
    #      both skipped if they already exist.
    task "bootstrap" {
      driver = "raw_exec"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      template {
        data        = <<-EOT
        {
          "postgres": {
            "host": "{{ range service "postgres" }}{{ .Address }}:{{ .Port }}{{ end }}",
            "user": "semaphore",
            "pass": "{{ key "semaphore/DB_PASSWORD" }}",
            "name": "semaphore",
            "options": {
              "sslmode": "disable"
            }
          },
          "dialect": "postgres",

          "port": ":3000",
          "web_host": "https://semaphore.cosmonautical.cloud",
          "tmp_path": "/opt/nomad/semaphore-tmp",

          "cookie_hash": "{{ key "semaphore/COOKIE_HASH" }}",
          "cookie_encryption": "{{ key "semaphore/COOKIE_ENCRYPTION" }}",
          "access_key_encryption": "{{ key "semaphore/ACCESS_KEY_ENCRYPTION" }}",

          "oidc_providers": {
            "keycloak": {
              "display_name": "Sign in with Keycloak",
              "provider_url": "https://auth.cosmonautical.cloud/realms/cosmonautical",
              "client_id": "semaphore",
              "client_secret": "{{ key "semaphore/OIDC_CLIENT_SECRET" }}",
              "redirect_url": "https://semaphore.cosmonautical.cloud/api/auth/oidc/keycloak/redirect"
            }
          }
        }
        EOT
        destination = "secrets/config.json"
      }

      template {
        data        = <<-EOT
        #!/bin/sh
        set -eu

        psql="/opt/homebrew/opt/postgresql@18/bin/psql"
        pg_host="{{ range service "postgres" }}{{ .Address }}{{ end }}"
        pg_port="{{ range service "postgres" }}{{ .Port }}{{ end }}"
        export PGPASSWORD="{{ key "postgres/PATRONI_SUPERUSER_PASSWORD" }}"

        "$psql" -h "$pg_host" -p "$pg_port" -U violet -d postgres -v ON_ERROR_STOP=1 \
          -v semaphore_pw="{{ key "semaphore/DB_PASSWORD" }}" <<'SQL'
        SELECT 'CREATE ROLE semaphore LOGIN PASSWORD ' || quote_literal(:'semaphore_pw')
          WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'semaphore')\gexec
        SELECT 'CREATE DATABASE semaphore OWNER semaphore'
          WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'semaphore')\gexec
        SQL

        venv_dir="/opt/nomad/semaphore-ansible-venv"
        if [ ! -x "$venv_dir/bin/ansible-playbook" ]; then
          /opt/homebrew/bin/python3.14 -m venv "$venv_dir"
          "$venv_dir/bin/pip" install --upgrade pip
          "$venv_dir/bin/pip" install "ansible==14.4.0"
        fi

        bin_dir="$NOMAD_ALLOC_DIR/semaphore"
        mkdir -p "$bin_dir"
        if [ ! -x "$bin_dir/semaphore" ]; then
          tmp_tgz="$NOMAD_TASK_DIR/semaphore.tar.gz"
          curl -fsSL -o "$tmp_tgz" \
            "https://github.com/semaphoreui/semaphore/releases/download/v2.19.12/semaphore_2.19.12_darwin_arm64.tar.gz"
          echo "08e9e4232299908cde1ca3806f9f1a1abadc54c3832b3e8747abff8d7c8abd80  $tmp_tgz" | shasum -a 256 -c -
          tar -xzf "$tmp_tgz" -C "$bin_dir" semaphore
          chmod 755 "$bin_dir/semaphore"
        fi

        cp "$NOMAD_SECRETS_DIR/config.json" "$bin_dir/config.json"

        if ! "$bin_dir/semaphore" user get --login violet --config "$bin_dir/config.json" >/dev/null 2>&1; then
          "$bin_dir/semaphore" user add --external --admin \
            --login violet --email "violet@cosmonautical.cloud" --name "Violet" \
            --config "$bin_dir/config.json"
        fi

        if ! "$bin_dir/semaphore" user get --login admin --config "$bin_dir/config.json" >/dev/null 2>&1; then
          "$bin_dir/semaphore" user add --admin \
            --login admin --email "admin@cosmonautical.cloud" --name "Break-glass admin" \
            --password "{{ key "semaphore/BOOTSTRAP_ADMIN_PASSWORD" }}" \
            --config "$bin_dir/config.json"
        fi
        EOT
        destination = "secrets/bootstrap.sh"
        perms       = "755"
      }

      config {
        command = "${NOMAD_SECRETS_DIR}/bootstrap.sh"
      }

      resources {
        cpu    = 2
        memory = 512
      }
    }

    task "semaphore" {
      driver = "raw_exec"

      config {
        command = "${NOMAD_ALLOC_DIR}/semaphore/semaphore"
        args    = ["server", "--config", "${NOMAD_ALLOC_DIR}/semaphore/config.json"]
      }

      env {
        # ansible venv first so `ansible-playbook`/`ansible-galaxy` resolve
        # there; system git (needed for repo cloning) comes from /usr/bin.
        PATH = "/opt/nomad/semaphore-ansible-venv/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
      }

      service {
        name = "semaphore"
        port = "http"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.semaphore.rule=Host(`semaphore.cosmonautical.cloud`)",
          "traefik.http.routers.semaphore.entrypoints=websecure",
          "traefik.http.routers.semaphore.tls.certresolver=cf-dns"
        ]

        check {
          name     = "ping"
          type     = "http"
          path     = "/api/ping"
          port     = "http"
          interval = "10s"
          timeout  = "2s"
        }
      }

      resources {
        cpu    = 2
        memory = 1024
      }
    }
  }
}
