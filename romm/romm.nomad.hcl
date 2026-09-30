job "romm" {
  datacenters = ["cosmonautical"]
  type        = "service"

  group "romm" {
    count = 1

    network {
      port "http" { static = 8086 }
    }

    # Idempotent bootstrap, re-run on every deploy: creates the `romm`
    # Postgres role/database on the shared postgres cluster if not already
    # there. RomM runs its own Alembic migrations against it on container
    # start - unlike guacamole's JDBC extension, no schema needs loading
    # here, and no user-bootstrap step either (OIDC_ALLOW_REGISTRATION
    # creates RomM's user record automatically on first Keycloak login).
    task "schema-init" {
      driver = "raw_exec"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      template {
        data        = <<-EOT
        #!/bin/sh
        set -eu

        psql="/opt/homebrew/opt/postgresql@18/bin/psql"
        host="{{ range service "postgres" }}{{ .Address }}{{ end }}"
        port="{{ range service "postgres" }}{{ .Port }}{{ end }}"

        export PGPASSWORD="{{ key "postgres/PATRONI_SUPERUSER_PASSWORD" }}"
        "$psql" -h "$host" -p "$port" -U violet -d postgres -v ON_ERROR_STOP=1 \
          -v romm_pw="{{ key "romm/DB_PASSWORD" }}" <<'SQL'
        SELECT 'CREATE ROLE romm LOGIN PASSWORD ' || quote_literal(:'romm_pw')
          WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'romm')\gexec
        SELECT 'CREATE DATABASE romm OWNER romm'
          WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'romm')\gexec
        SQL
        EOT
        destination = "secrets/schema-init.sh"
        perms       = "755"
      }

      config {
        command = "${NOMAD_SECRETS_DIR}/schema-init.sh"
      }

      resources {
        cpu    = 1
        memory = 64
      }
    }

    # Idempotent bootstrap, re-run on every deploy: RomM 5.x no longer
    # auto-detects a `{platform}/roms/{game}` + `{platform}/bios` layout (our
    # library's actual structure) - without this file declaring it,
    # config_manager logs a CRITICAL and the startup script exits, which
    # looks from Nomad's side like a plain crash loop (exit 0, no visible
    # error unless you catch a still-running container and read past
    # "Running database migrations"). Found 2026-09-30 - see CHANGELOG.md.
    # Written straight onto the NFS-backed config/ volume, not into the
    # container's own /local - the romm task mounts the same host path.
    task "ensure-config" {
      driver = "raw_exec"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      template {
        data        = <<-EOT
        #!/bin/sh
        set -eu
        mkdir -p /Volumes/Cosmonautical/romm/config
        cat > /Volumes/Cosmonautical/romm/config/config.yml <<'YAML'
        filesystem:
          structure:
            default: "{platform}/roms/{game}"
            firmware: "{platform}/bios"
        YAML
        EOT
        destination = "local/ensure-config.sh"
        perms       = "755"
      }

      config {
        command = "${NOMAD_TASK_DIR}/ensure-config.sh"
      }

      resources {
        cpu    = 1
        memory = 32
      }
    }

    task "romm" {
      driver = "container"

      config {
        image = "rommapp/romm:5.3.1"
        ports = ["http"]

        # /Volumes/ROMs is the same NFS-backed ROM library nextcloud-roms-scan
        # indexes into Nextcloud. Originally mounted read-only so RomM
        # couldn't be a second writer into it, but RomM's own "add platform"
        # UI needs to create the platform's folder on disk - flipped to rw
        # 2026-09-30 once that was actually wanted (see CHANGELOG.md).
        volumes = [
          "/Volumes/ROMs:/romm/library",
          "/Volumes/Cosmonautical/romm/assets:/romm/assets",
          "/Volumes/Cosmonautical/romm/config:/romm/config",
          "/Volumes/Cosmonautical/romm/resources:/romm/resources"
        ]
      }

      env {
        ROMM_DB_DRIVER = "postgresql"
        DB_PORT        = "5432"
        DB_NAME        = "romm"
        DB_USER        = "romm"

        ROMM_PORT = "8086"

        # Auth: Keycloak OIDC (confidential client, authorization code flow -
        # unlike guacamole's OpenID extension, RomM supports a client secret
        # directly, so no public/implicit-flow workaround needed). RomM
        # creates its own user record on first login (OIDC_ALLOW_REGISTRATION
        # defaults true) - no JDBC-style authorization bootstrap required.
        OIDC_ENABLED   = "true"
        OIDC_CLIENT_ID = "romm"

        # Default (4) spawns 4 gunicorn workers on top of nginx, the RQ
        # worker/scan-worker, and the cron scheduler - all separate Python
        # processes loading the full app/SQLAlchemy metadata. That got a
        # worker OOM-killed at this job's original memory = 768 (see
        # CHANGELOG.md, 2026-09-30). 2 is plenty for single-tenant use and
        # keeps the footprint down even after the memory bump below.
        WEB_SERVER_CONCURRENCY = "2"
      }

      # Non-sensitive, deployment-specific config (URLs) - Nomad Variables,
      # not hardcoded here, so this spec is reusable against a different
      # environment/domain without editing the .hcl file. Sensitive values
      # stay in Consul KV (below) - see ../.agents/AGENTS.md's "Non-secret
      # config (Nomad Variables)" section. Populate via the HTTP API:
      # PUT /v1/var/nomad/jobs/romm {"Items": {"ROMM_BASE_URL": "...", ...}}
      # with all four keys read below.
      template {
        data        = <<EOT
{{ with nomadVar "nomad/jobs/romm" }}
ROMM_BASE_URL={{ .ROMM_BASE_URL }}
OIDC_PROVIDER={{ .OIDC_PROVIDER }}
OIDC_REDIRECT_URI={{ .OIDC_REDIRECT_URI }}
OIDC_SERVER_APPLICATION_URL={{ .OIDC_SERVER_APPLICATION_URL }}
{{ end }}
EOT
        destination = "local/romm-config.env"
        env         = true
      }

      template {
        data        = <<EOT
DB_HOST={{ range service "postgres" }}{{ .Address }}{{ end }}
DB_PASSWD={{ key "romm/DB_PASSWORD" }}
REDIS_HOST={{ range service "redis" }}{{ .Address }}{{ end }}
REDIS_PORT={{ range service "redis" }}{{ .Port }}{{ end }}
REDIS_PASSWORD={{ key "redis/PASSWORD" }}
ROMM_AUTH_SECRET_KEY={{ key "romm/AUTH_SECRET_KEY" }}
OIDC_CLIENT_SECRET={{ key "romm/OIDC_CLIENT_SECRET" }}
EOT
        destination = "secrets/romm.env"
        env         = true
      }

      service {
        name = "romm"
        port = "http"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.romm.rule=Host(`roms.cosmonautical.cloud`)",
          "traefik.http.routers.romm.entrypoints=websecure",
          "traefik.http.routers.romm.tls.certresolver=cf-dns"
        ]

        check {
          name     = "tcp"
          type     = "tcp"
          port     = "http"
          interval = "30s"
          timeout  = "10s"
        }
      }

      resources {
        cpu    = 2
        memory = 1536
      }
    }
  }
}
