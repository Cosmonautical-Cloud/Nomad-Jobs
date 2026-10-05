# Home Assistant stack: one job, three groups, each free to land on a
# different node. Startup order is mqtt -> home-assistant -> node-red, enforced
# by each downstream group's `wait-for-*` prestart polling Consul health for
# the service it depends on. See README.md for the full picture.
locals {
  # Shared NFS root for every group's persistent state.
  data_root = "/Volumes/Cosmonautical/home-assistant"

  zigbee2mqtt_version = "2.14.2"
  ldap3_version       = "2.9.1"
}

job "home-assistant" {
  datacenters = ["cosmonautical"]
  type        = "service"

  # MQTT broker + Zigbee bridge. Pinned to the node with the Zigbee USB
  # coordinator: hosts in the `iot` inventory group that also publish the
  # adapter's serial device in node meta (both set through Nomadable - see
  # README's "Host prerequisites").
  group "mqtt" {
    count = 1

    constraint {
      attribute = "${meta.inventory_groups}"
      operator  = "set_contains"
      value     = "iot"
    }

    constraint {
      attribute = "${meta.zigbee_adapter}"
      operator  = "is_set"
    }

    constraint {
      attribute = "${meta.zigbee_adapter_type}"
      operator  = "is_set"
    }

    # Static: Home Assistant's MQTT integration is configured in its UI with
    # a fixed host:port, and containers can't resolve *.service.consul.
    network {
      port "mqtt" { static = 1883 }
      port "zigbee2mqtt" {}
    }

    # Creates the NFS state directories (the container driver can't bind-mount
    # a missing path) and installs zigbee2mqtt into the alloc dir. Apple's
    # container VMs have no USB passthrough, so zigbee2mqtt runs natively on
    # the host under Homebrew's node@24 rather than in a container.
    task "prepare" {
      driver = "raw_exec"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      env {
        PATH = "/opt/homebrew/opt/node@24/bin:/usr/bin:/bin"
      }

      config {
        command = "/bin/sh"
        args = [
          "-c",
          <<-EOT
          set -eu
          # NFS squashes ownership, so open the dirs up for the containers'
          # own uids (mosquitto runs as 1883).
          mkdir -p ${local.data_root}/mosquitto/data ${local.data_root}/zigbee2mqtt
          chmod 0777 ${local.data_root}/mosquitto/data

          prefix="$NOMAD_ALLOC_DIR/zigbee2mqtt"
          if [ ! -f "$prefix/node_modules/zigbee2mqtt/index.js" ]; then
            npm install --prefix "$prefix" --omit=dev --no-audit --no-fund \
              zigbee2mqtt@${local.zigbee2mqtt_version}
          fi
          EOT
        ]
      }

      resources {
        cpu    = 1
        memory = 512
      }
    }

    task "mosquitto" {
      driver = "container"

      config {
        image      = "eclipse-mosquitto:2.0.22"
        ports      = ["mqtt"]
        entrypoint = "/bin/sh"

        # The container driver doesn't mount Nomad's /local or /secrets, so
        # the config and password file are written inside the container from
        # env vars. mosquitto_passwd -U hashes the plaintext file in place.
        args = [
          "-c",
          <<-EOT
          set -eu
          conf=/mosquitto/config
          printf 'homeassistant:%s\nzigbee2mqtt:%s\nnodered:%s\n' \
            "$MQTT_HOMEASSISTANT_PASSWORD" "$MQTT_ZIGBEE2MQTT_PASSWORD" "$MQTT_NODERED_PASSWORD" \
            > "$conf/passwd"
          mosquitto_passwd -U "$conf/passwd"
          chown mosquitto:mosquitto "$conf/passwd"
          chmod 0700 "$conf/passwd"
          cat > "$conf/mosquitto.conf" <<'CONF'
          listener 1883
          allow_anonymous false
          password_file /mosquitto/config/passwd
          persistence true
          persistence_location /mosquitto/data/
          log_dest stdout
          CONF
          exec mosquitto -c "$conf/mosquitto.conf"
          EOT
        ]

        volumes = [
          "${local.data_root}/mosquitto/data:/mosquitto/data",
        ]
      }

      template {
        data        = <<EOT
MQTT_HOMEASSISTANT_PASSWORD={{ key "home-assistant/MQTT_HOMEASSISTANT_PASSWORD" }}
MQTT_ZIGBEE2MQTT_PASSWORD={{ key "home-assistant/MQTT_ZIGBEE2MQTT_PASSWORD" }}
MQTT_NODERED_PASSWORD={{ key "home-assistant/MQTT_NODERED_PASSWORD" }}
EOT
        destination = "secrets/mosquitto.env"
        env         = true
      }

      service {
        name = "mqtt"
        port = "mqtt"

        check {
          name     = "tcp"
          type     = "tcp"
          port     = "mqtt"
          interval = "30s"
          timeout  = "5s"
        }
      }

      resources {
        cpu    = 1
        memory = 64
      }
    }

    task "zigbee2mqtt" {
      driver = "raw_exec"

      config {
        command = "/opt/homebrew/opt/node@24/bin/node"
        args    = ["${NOMAD_ALLOC_DIR}/zigbee2mqtt/node_modules/zigbee2mqtt/index.js"]
      }

      # Every setting zigbee2mqtt needs comes from ZIGBEE2MQTT_CONFIG_* env
      # vars, which it writes back into its configuration.yaml on start.
      # Z2M_ONBOARD_NO_SERVER skips the first-run setup web page.
      env {
        ZIGBEE2MQTT_DATA      = "${local.data_root}/zigbee2mqtt"
        Z2M_ONBOARD_NO_SERVER = "1"

        ZIGBEE2MQTT_CONFIG_SERIAL_PORT    = "${meta.zigbee_adapter}"
        ZIGBEE2MQTT_CONFIG_SERIAL_ADAPTER = "${meta.zigbee_adapter_type}"

        # Mosquitto publishes on every host interface, and 127.0.0.1 keeps
        # Homebrew node clear of macOS's Local Network permission prompt.
        ZIGBEE2MQTT_CONFIG_MQTT_SERVER = "mqtt://127.0.0.1:${NOMAD_PORT_mqtt}"
        ZIGBEE2MQTT_CONFIG_MQTT_USER   = "zigbee2mqtt"

        ZIGBEE2MQTT_CONFIG_HOMEASSISTANT_ENABLED = "true"

        ZIGBEE2MQTT_CONFIG_FRONTEND_ENABLED = "true"
        ZIGBEE2MQTT_CONFIG_FRONTEND_PORT    = "${NOMAD_PORT_zigbee2mqtt}"

        # Generated once on first start, then persisted in configuration.yaml.
        ZIGBEE2MQTT_CONFIG_ADVANCED_NETWORK_KEY = "GENERATE"
        ZIGBEE2MQTT_CONFIG_ADVANCED_PAN_ID      = "GENERATE"
        ZIGBEE2MQTT_CONFIG_ADVANCED_EXT_PAN_ID  = "GENERATE"
      }

      template {
        data        = <<EOT
ZIGBEE2MQTT_CONFIG_MQTT_PASSWORD={{ key "home-assistant/MQTT_ZIGBEE2MQTT_PASSWORD" }}
ZIGBEE2MQTT_CONFIG_FRONTEND_AUTH_TOKEN={{ key "home-assistant/ZIGBEE2MQTT_FRONTEND_TOKEN" }}
EOT
        destination = "secrets/zigbee2mqtt.env"
        env         = true
      }

      # Frontend is LAN-only (no Traefik route); pairing can also be started
      # from Home Assistant's "Permit join" switch.
      service {
        name = "zigbee2mqtt"
        port = "zigbee2mqtt"

        check {
          name     = "tcp"
          type     = "tcp"
          port     = "zigbee2mqtt"
          interval = "30s"
          timeout  = "5s"
        }
      }

      resources {
        cpu    = 1
        memory = 256
      }
    }
  }

  group "home-assistant" {
    count = 1

    network {
      port "http" { to = 8123 }
    }

    task "wait-for-mqtt" {
      driver = "raw_exec"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      config {
        command = "/bin/sh"
        args = [
          "-c",
          "until curl -fsS 'http://127.0.0.1:8500/v1/health/service/mqtt?passing' | grep -q ServiceID; do sleep 5; done",
        ]
      }

      resources {
        cpu    = 1
        memory = 16
      }
    }

    # Idempotent bootstrap, re-run on every deploy: creates the
    # `homeassistant` role/database on the shared postgres cluster for the
    # recorder (SQLite on NFS is a locking hazard). Home Assistant creates its
    # own tables.
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
          -v ha_pw="{{ key "home-assistant/DB_PASSWORD" }}" <<'SQL'
        SELECT 'CREATE ROLE homeassistant LOGIN PASSWORD ' || quote_literal(:'ha_pw')
          WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'homeassistant')\gexec
        SELECT 'CREATE DATABASE homeassistant OWNER homeassistant'
          WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'homeassistant')\gexec
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

    # Writes the managed configuration.yaml and the LDAP auth script onto the
    # NFS config dir (the container driver doesn't mount Nomad's /local), and
    # vendors the pure-Python ldap3 library next to the script - the Home
    # Assistant image has no LDAP client of its own.
    task "ensure-config" {
      driver = "raw_exec"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      template {
        data        = <<EOT
# Managed by the home-assistant Nomad job (ensure-config task) and overwritten
# on every deploy. Put additional YAML in packages/<name>.yaml instead.
default_config:

homeassistant:
  external_url: !env_var EXTERNAL_URL
  packages: !include_dir_named packages
  auth_providers:
    # LDAP: simple bind as the user, then require membership in cn=Admins.
    # Home Assistant only passes username/password to the command, so the
    # LDAP URI travels as an argument.
    - type: command_line
      name: Cosmonautical
      command: /usr/local/bin/python3
      args:
        - /config/ldap-auth/ldap_auth.py
        - !env_var LDAP_URI
      meta: true
    # Local accounts: onboarding's owner account, kept as a break-glass login.
    - type: homeassistant

http:
  use_x_forwarded_for: true
  # Traefik reaches the container through the host's published port, so
  # requests arrive from the LAN or from the container network's gateway.
  trusted_proxies:
    - 10.10.37.0/24
    - 192.168.65.0/24

recorder:
  db_url: !env_var RECORDER_DB_URL

automation: !include automations.yaml
script: !include scripts.yaml
scene: !include scenes.yaml
EOT
        destination = "local/configuration.yaml"
      }

      template {
        data        = <<EOT
"""Home Assistant command_line auth provider backed by OpenLDAP.

Home Assistant runs this with only `username` and `password` in the
environment; the LDAP URI is argv[1]. Exit status 0 allows the login, and
the printed `key = value` lines become the user's metadata.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))

from ldap3 import BASE, Connection, Server
from ldap3.core.exceptions import LDAPException
from ldap3.utils.conv import escape_filter_chars
from ldap3.utils.dn import escape_rdn

USERS_DN = "ou=users,dc=cosmonautical,dc=cloud"
ADMIN_GROUP_DN = "cn=Admins,ou=groups,dc=cosmonautical,dc=cloud"


def main():
    username = os.environ.get("username", "")
    password = os.environ.get("password", "")
    # slapd treats a bind with an empty password as an anonymous bind, which
    # succeeds - never let that through as a login.
    if not username or not password:
        return 1

    user_dn = f"cn={escape_rdn(username)},{USERS_DN}"
    try:
        conn = Connection(
            Server(sys.argv[1], connect_timeout=5),
            user=user_dn,
            password=password,
            receive_timeout=5,
        )
        if not conn.bind():
            return 1

        # Check the group's own `member` list rather than the user's memberOf,
        # which the memberof overlay only maintains for later changes.
        conn.search(
            ADMIN_GROUP_DN,
            f"(member={escape_filter_chars(user_dn)})",
            search_scope=BASE,
        )
        if not conn.entries:
            return 1

        conn.search(user_dn, "(objectClass=*)", search_scope=BASE, attributes=["displayName", "cn"])
        entry = conn.entries[0]
        name = entry.displayName.value if entry.displayName else entry.cn.value
    except LDAPException:
        return 1

    print(f"name = {name}")
    print("group = system-admin")
    return 0


if __name__ == "__main__":
    sys.exit(main())
EOT
        destination = "local/ldap_auth.py"
      }

      config {
        command = "/bin/sh"
        args = [
          "-c",
          <<-EOT
          set -eu
          config=${local.data_root}/config
          mkdir -p "$config/packages" "$config/ldap-auth"
          cp "$NOMAD_TASK_DIR/configuration.yaml" "$config/configuration.yaml"
          cp "$NOMAD_TASK_DIR/ldap_auth.py" "$config/ldap-auth/ldap_auth.py"

          # Files Home Assistant's UI editors own: create once, never overwrite.
          [ -f "$config/automations.yaml" ] || echo '[]' > "$config/automations.yaml"
          [ -f "$config/scripts.yaml" ] || : > "$config/scripts.yaml"
          [ -f "$config/scenes.yaml" ] || : > "$config/scenes.yaml"

          lib="$config/ldap-auth/lib"
          if [ ! -d "$lib/ldap3-${local.ldap3_version}.dist-info" ]; then
            rm -rf "$lib"
            /opt/homebrew/bin/python3 -m pip install --quiet --disable-pip-version-check \
              --target "$lib" ldap3==${local.ldap3_version}
          fi
          EOT
        ]
      }

      resources {
        cpu    = 1
        memory = 128
      }
    }

    task "home-assistant" {
      driver = "container"

      config {
        image = "ghcr.io/home-assistant/home-assistant:2026.9.4"
        ports = ["http"]

        volumes = [
          "${local.data_root}/config:/config",
        ]
      }

      # Non-sensitive, deployment-specific config - Nomad Variables, see
      # README's "Nomad Variables" table.
      template {
        data        = <<EOT
{{ with nomadVar "nomad/jobs/home-assistant" }}
EXTERNAL_URL={{ .HOME_ASSISTANT_URL }}
{{ end }}
EOT
        destination = "local/home-assistant-config.env"
        env         = true
      }

      template {
        data        = <<EOT
RECORDER_DB_URL=postgresql://homeassistant:{{ key "home-assistant/DB_PASSWORD" }}@{{ range service "postgres" }}{{ .Address }}:{{ .Port }}{{ end }}/homeassistant
LDAP_URI=ldap://{{ range service "openldap" }}{{ .Address }}:{{ .Port }}{{ end }}
EOT
        destination = "secrets/home-assistant.env"
        env         = true
      }

      service {
        name = "home-assistant"
        port = "http"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.home-assistant.rule=Host(`casa.cosmonautical.cloud`)",
          "traefik.http.routers.home-assistant.entrypoints=websecure",
          "traefik.http.routers.home-assistant.tls.certresolver=cf-dns",
        ]

        check {
          name     = "manifest"
          type     = "http"
          path     = "/manifest.json"
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

  group "node-red" {
    count = 1

    network {
      port "http" { to = 1880 }
    }

    task "wait-for-home-assistant" {
      driver = "raw_exec"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      config {
        command = "/bin/sh"
        args = [
          "-c",
          "until curl -fsS 'http://127.0.0.1:8500/v1/health/service/home-assistant?passing' | grep -q ServiceID; do sleep 5; done",
        ]
      }

      resources {
        cpu    = 1
        memory = 16
      }
    }

    # Writes the managed settings.js onto the NFS data dir. It holds no
    # secrets - everything sensitive is read from env at runtime.
    task "ensure-config" {
      driver = "raw_exec"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      template {
        data        = <<EOT
// Managed by the home-assistant Nomad job (node-red ensure-config task) and
// overwritten on every deploy.
const env = process.env;
const issuer = env.OIDC_ISSUER.replace(/\/$/, "");
const publicUrl = env.PUBLIC_URL.replace(/\/$/, "");
const adminGroup = "Admins";

// Usernames whose ID token carried the admin group. Node-RED looks users up
// by name only, so the group check happens in `verify` and is remembered
// here for the `users` lookup that follows it.
const admins = new Set();

function idTokenClaims(idToken) {
  return JSON.parse(Buffer.from(idToken.split(".")[1], "base64url").toString());
}

module.exports = {
  uiPort: 1880,
  flowFile: "flows.json",
  credentialSecret: env.NODE_RED_CREDENTIAL_SECRET,

  adminAuth: {
    type: "strategy",
    strategy: {
      name: "openidconnect",
      label: "Sign in with Cosmonautical",
      icon: "fa-sign-in",
      strategy: require("passport-openidconnect").Strategy,
      options: {
        issuer: issuer,
        authorizationURL: issuer + "/protocol/openid-connect/auth",
        tokenURL: issuer + "/protocol/openid-connect/token",
        userInfoURL: issuer + "/protocol/openid-connect/userinfo",
        clientID: "node-red",
        clientSecret: env.OIDC_CLIENT_SECRET,
        callbackURL: publicUrl + "/auth/strategy/callback",
        scope: ["openid", "profile", "email"],
        proxy: true,
        // Five arguments: passport-openidconnect picks what to pass by the
        // callback's arity, and this form includes the raw ID token.
        verify: function (iss, profile, context, idToken, done) {
          const claims = idTokenClaims(idToken);
          const groups = claims.groups || [];
          const username = claims.preferred_username;
          if (groups.includes(adminGroup) || groups.includes("/" + adminGroup)) {
            admins.add(username);
          }
          done(null, { username: username });
        },
      },
    },
    users: function (username) {
      return Promise.resolve(admins.has(username) ? { username: username, permissions: "*" } : null);
    },
  },
};
EOT
        destination = "local/settings.js"
      }

      config {
        command = "/bin/sh"
        args = [
          "-c",
          <<-EOT
          set -eu
          data=${local.data_root}/node-red
          mkdir -p "$data"
          # NFS squashes ownership; the image runs as uid 1000.
          chmod 0777 "$data"
          cp "$NOMAD_TASK_DIR/settings.js" "$data/settings.js"
          EOT
        ]
      }

      resources {
        cpu    = 1
        memory = 16
      }
    }

    task "node-red" {
      driver = "container"

      config {
        image      = "nodered/node-red:5.0.7"
        ports      = ["http"]
        entrypoint = "/bin/sh"

        # Installs the SSO strategy and the Home Assistant nodes into
        # /data/node_modules (alongside anything added from the palette),
        # then hands off to the image's own entrypoint.
        args = [
          "-c",
          <<-EOT
          set -eu
          cd /data
          npm install --cache /data/.npm --omit=dev --no-audit --no-fund \
            passport-openidconnect@0.1.2 \
            node-red-contrib-home-assistant-websocket@0.81.0
          cd /usr/src/node-red
          exec ./entrypoint.sh
          EOT
        ]

        volumes = [
          "${local.data_root}/node-red:/data",
        ]
      }

      template {
        data        = <<EOT
{{ with nomadVar "nomad/jobs/home-assistant" }}
PUBLIC_URL={{ .NODE_RED_URL }}
OIDC_ISSUER={{ .OIDC_ISSUER }}
{{ end }}
EOT
        destination = "local/node-red-config.env"
        env         = true
      }

      template {
        data        = <<EOT
OIDC_CLIENT_SECRET={{ key "home-assistant/NODE_RED_OIDC_CLIENT_SECRET" }}
NODE_RED_CREDENTIAL_SECRET={{ key "home-assistant/NODE_RED_CREDENTIAL_SECRET" }}
EOT
        destination = "secrets/node-red.env"
        env         = true
      }

      service {
        name = "node-red"
        port = "http"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.node-red.rule=Host(`node-red.cosmonautical.cloud`)",
          "traefik.http.routers.node-red.entrypoints=websecure",
          "traefik.http.routers.node-red.tls.certresolver=cf-dns",
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
        cpu    = 1
        memory = 512
      }
    }
  }
}
