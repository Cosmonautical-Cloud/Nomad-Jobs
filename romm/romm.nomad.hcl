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

    task "romm" {
      driver = "container"

      config {
        image = "rommapp/romm:5.3.1"
        ports = ["http"]

        # /Volumes/ROMs is the same NFS-backed ROM library nextcloud-roms-scan
        # indexes into Nextcloud - mounted read-only here so RomM (library
        # browsing/metadata/play) can't be a second, less-trusted writer into
        # a library Nextcloud also manages. Flip to rw if RomM-side library
        # organization/renaming ends up wanted.
        volumes = [
          "/Volumes/ROMs:/romm/library:ro",
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
        memory = 768
      }
    }
  }
}
