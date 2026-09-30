job "guacamole" {
  datacenters = ["cosmonautical"]
  type        = "service"

  group "guacamole" {
    count = 1

    network {
      port "http"  { static = 8084 }
      port "guacd" { static = 4822 }
    }

    # Idempotent bootstrap, re-run on every deploy:
    #  1. Creates the `guacamole` Postgres role/database on the cluster's
    #     existing Patroni cluster (postgres.nomad.hcl) if not already there.
    #  2. Loads the guacamole-auth-jdbc-postgresql schema, generated fresh
    #     from the exact image version below via its own `initdb.sh` helper
    #     (not a hand-copied SQL file, so it always matches), if not already
    #     loaded.
    #  3. Deletes the schema's seeded `guacadmin`/`guacadmin` local-login
    #     account - login here is Keycloak SSO only, and that account would
    #     otherwise be a full-admin backdoor around it.
    #  4. Ensures a Guacamole user record exists for violet's Keycloak/LDAP
    #     identity (its password is random and never checked - the OpenID
    #     extension authenticates, this JDBC record only authorizes), with
    #     `ADMINISTER` system permission.
    #  5. Ensures a VNC connection exists for each of the 5 cluster Macs
    #     (macOS Screen Sharing, connection parameters kept in sync with
    #     Consul KV `guacamole/MACOS_VNC_USERNAME`/`MACOS_VNC_PASSWORD` on
    #     every run), with violet granted READ on each.
    # No one else who can log into the cosmonautical Keycloak realm gets any
    # connections, since no other Guacamole user record exists.
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
        container="/opt/homebrew/bin/container"
        host="{{ range service "postgres" }}{{ .Address }}{{ end }}"
        port="{{ range service "postgres" }}{{ .Port }}{{ end }}"

        # 1. Role + database (idempotent)
        export PGPASSWORD="{{ key "postgres/PATRONI_SUPERUSER_PASSWORD" }}"
        "$psql" -h "$host" -p "$port" -U violet -d postgres -v ON_ERROR_STOP=1 \
          -v guac_pw="{{ key "guacamole/DB_PASSWORD" }}" <<'SQL'
        SELECT 'CREATE ROLE guacamole LOGIN PASSWORD ' || quote_literal(:'guac_pw')
          WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'guacamole')\gexec
        SELECT 'CREATE DATABASE guacamole OWNER guacamole'
          WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'guacamole')\gexec
        SQL

        export PGPASSWORD="{{ key "guacamole/DB_PASSWORD" }}"

        # 2. Schema (idempotent - only loads if guacamole_user is missing)
        schema_present=$("$psql" -h "$host" -p "$port" -U guacamole -d guacamole -tAc \
          "SELECT to_regclass('public.guacamole_user') IS NOT NULL")

        if [ "$schema_present" != "t" ]; then
          "$container" run --rm guacamole/guacamole:1.6.0 /opt/guacamole/bin/initdb.sh --postgresql \
            | "$psql" -h "$host" -p "$port" -U guacamole -d guacamole -v ON_ERROR_STOP=1
        fi

        # 3-5. Bootstrap: remove the seeded local-login backdoor, ensure
        # violet's SSO-linked profile, ensure the 5 VNC connections + grants.
        # Random throwaway password for violet's JDBC row - never checked,
        # since OpenID (not JDBC) authenticates this user.
        salt_hex=$(/usr/bin/openssl rand -hex 32)
        secret_hex=$(/usr/bin/openssl rand -hex 32)
        hash_hex=$(printf '%s' "$${secret_hex}$${salt_hex}" | /usr/bin/xxd -r -p | /usr/bin/openssl dgst -sha256 -binary | /usr/bin/xxd -p -c 256 | tr -d '\n')

        "$psql" -h "$host" -p "$port" -U guacamole -d guacamole -v ON_ERROR_STOP=1 \
          -v hash_hex="$hash_hex" -v salt_hex="$salt_hex" \
          -v vnc_user="{{ key "guacamole/MACOS_VNC_USERNAME" }}" \
          -v vnc_pw="{{ key "guacamole/MACOS_VNC_PASSWORD" }}" <<'SQL'
        DO $do$
        DECLARE
          v_entity_id integer;
          h RECORD;
          conn_id integer;
        BEGIN
          DELETE FROM guacamole_entity WHERE name = 'guacadmin' AND type = 'USER';

          SELECT entity_id INTO v_entity_id FROM guacamole_entity WHERE name = 'violet' AND type = 'USER';
          IF v_entity_id IS NULL THEN
            INSERT INTO guacamole_entity (name, type) VALUES ('violet', 'USER')
              RETURNING entity_id INTO v_entity_id;
            INSERT INTO guacamole_user (entity_id, password_hash, password_salt, password_date)
              VALUES (v_entity_id, decode(:'hash_hex', 'hex'), decode(:'salt_hex', 'hex'), CURRENT_TIMESTAMP);
            INSERT INTO guacamole_system_permission (entity_id, permission)
              VALUES (v_entity_id, 'ADMINISTER');
          END IF;

          FOR h IN
            SELECT * FROM (VALUES
              ('cassiopeia', '10.10.37.18'),
              ('taurus',     '10.10.37.127'),
              ('betelgeuse', '10.10.37.193'),
              ('galileo',    '10.10.37.45'),
              ('hopper',     '10.10.37.51')
            ) AS t(name, ip)
          LOOP
            SELECT connection_id INTO conn_id FROM guacamole_connection
              WHERE connection_name = h.name AND parent_id IS NULL;

            IF conn_id IS NULL THEN
              INSERT INTO guacamole_connection (connection_name, protocol)
                VALUES (h.name, 'vnc') RETURNING connection_id INTO conn_id;
            END IF;

            INSERT INTO guacamole_connection_parameter (connection_id, parameter_name, parameter_value)
              VALUES
                (conn_id, 'hostname', h.ip),
                (conn_id, 'port', '5900'),
                (conn_id, 'username', :'vnc_user'),
                (conn_id, 'password', :'vnc_pw')
              ON CONFLICT (connection_id, parameter_name)
              DO UPDATE SET parameter_value = EXCLUDED.parameter_value;

            IF NOT EXISTS (
              SELECT 1 FROM guacamole_connection_permission
              WHERE entity_id = v_entity_id AND connection_id = conn_id AND permission = 'READ'
            ) THEN
              INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
                VALUES (v_entity_id, conn_id, 'READ');
            END IF;
          END LOOP;
        END
        $do$ LANGUAGE plpgsql;
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

    task "guacd" {
      driver = "container"

      config {
        image = "guacamole/guacd:1.6.0"
        ports = ["guacd"]
      }

      service {
        name = "guacd"
        port = "guacd"

        check {
          name     = "tcp"
          type     = "tcp"
          port     = "guacd"
          interval = "10s"
          timeout  = "2s"
        }
      }

      resources {
        cpu    = 1
        memory = 128
      }
    }

    task "guacamole" {
      driver = "container"

      config {
        image = "guacamole/guacamole:1.6.0"
        ports = ["http"]
      }

      env {
        GUACD_HOSTNAME = "guacd.service.consul"
        GUACD_PORT     = "4822"
        WEBAPP_CONTEXT = "ROOT"

        # Auth: Keycloak OIDC (SSO, implicit flow - guacamole-auth-sso-openid
        # has no client-secret/PKCE support, so the Keycloak client must be
        # public with Implicit Flow enabled) verifies identity; JDBC/Postgres
        # below owns authorization. A user who authenticates via Keycloak but
        # has no matching row in guacamole_user gets zero connections - see
        # the schema-init task above for the bootstrap that creates exactly
        # one such row, for violet.
        OPENID_AUTHORIZATION_ENDPOINT = "https://auth.cosmonautical.cloud/realms/cosmonautical/protocol/openid-connect/auth"
        OPENID_JWKS_ENDPOINT          = "https://auth.cosmonautical.cloud/realms/cosmonautical/protocol/openid-connect/certs"
        OPENID_ISSUER                 = "https://auth.cosmonautical.cloud/realms/cosmonautical"
        OPENID_CLIENT_ID              = "guacamole"
        OPENID_REDIRECT_URI           = "https://guac.cosmonautical.cloud/"
        OPENID_USERNAME_CLAIM_TYPE    = "preferred_username"
        OPENID_SCOPE                  = "openid email profile"
      }

      template {
        data        = <<EOT
POSTGRESQL_HOSTNAME={{ range service "postgres" }}{{ .Address }}{{ end }}
POSTGRESQL_PORT={{ range service "postgres" }}{{ .Port }}{{ end }}
POSTGRESQL_DATABASE=guacamole
POSTGRESQL_USERNAME=guacamole
POSTGRESQL_PASSWORD={{ key "guacamole/DB_PASSWORD" }}
EOT
        destination = "secrets/db.env"
        env         = true
      }

      service {
        name = "guacamole"
        port = "http"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.guacamole.rule=Host(`guac.cosmonautical.cloud`)",
          "traefik.http.routers.guacamole.entrypoints=websecure",
          "traefik.http.routers.guacamole.tls.certresolver=cf-dns"
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
        memory = 1024
      }
    }
  }
}
