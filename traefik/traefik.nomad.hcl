job "traefik" {
  datacenters = ["cosmonautical"]
  type = "service"

  group "ingress" {
    count = 1

    ephemeral_disk {
      size    = 200
      migrate = true
      sticky  = true
    }

    network {
      port "dashboard"  { static = 8081 }
      port "postgres"   { static = 15432 }
      port "web"        { static = 8080 }
      port "websecure"  { static = 8443 }
      port "minecraft"  { static = 25565 }
      port "bedrock"    { static = 19132 }
      port "valheim-game"  { static = 2456 }
      port "valheim-query" { static = 2457 }
      port "valheim-extra" { static = 2458 }
    }

    task "update-port-forward" {
      driver = "raw_exec"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      template {
        data        = <<EOT
{{ with nomadVar "nomad/jobs/minecraft" }}MINECRAFT_JAVA_RULE_ID={{ .udm_java_rule_id }}
MINECRAFT_BEDROCK_RULE_ID={{ .udm_bedrock_rule_id }}
{{ end }}
{{ with nomadVar "nomad/jobs/valheim" }}VALHEIM_RULE_ID={{ .udm_rule_id }}
{{ end }}
EOT
        destination = "secrets/minecraft-rules.env"
        env         = true
      }

      template {
        data        = <<EOT
#!/bin/sh
set -eu

unifi_host="https://10.10.37.1"
cookie_jar="$NOMAD_SECRETS_DIR/unifi-cookies.txt"

login_headers=$(curl -sk -c "$cookie_jar" -D - -o /dev/null -X POST "$unifi_host/api/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"nomad","password":"{{ key "unifi/NOMAD_USER_PASSWORD" }}"}')

csrf=$(echo "$login_headers" | grep -i "^x-csrf-token" | tail -1 | awk '{print $2}' | tr -d '\r')

host_ip="$NOMAD_IP_web"
case "$host_ip" in
  *:*|"")
    host_ip=$(/sbin/ifconfig | awk '/inet /{print $2}' | grep -v '^127\.' | head -1)
    ;;
esac

update_rule() {
  rule_id="$1"
  fwd_ip="$2"

  current_rule=$(curl -sk -b "$cookie_jar" -H "X-CSRF-Token: $csrf" \
    "$unifi_host/proxy/network/api/s/default/rest/portforward/$rule_id")

  updated_rule=$(echo "$current_rule" | python3 -c "
import json, sys
d = json.load(sys.stdin)
rule = d['data'][0]
rule['fwd'] = '$fwd_ip'
print(json.dumps(rule))
")

  attempt=0
  while [ "$attempt" -lt 5 ]; do
    attempt=$((attempt + 1))
    response=$(curl -sk -b "$cookie_jar" -H "X-CSRF-Token: $csrf" -H "Content-Type: application/json" \
      -X PUT "$unifi_host/proxy/network/api/s/default/rest/portforward/$rule_id" \
      -d "$updated_rule" -w "\n%%{http_code}")
    code=$(echo "$response" | tail -1)
    body=$(echo "$response" | sed '$d')
    if [ "$code" = "200" ]; then
      echo "port-forward update ($rule_id -> $fwd_ip): 200"
      return 0
    fi
    echo "port-forward update ($rule_id -> $fwd_ip) attempt $attempt failed: HTTP $code: $body" >&2
    sleep 3
  done

  echo "port-forward update ($rule_id -> $fwd_ip) failed after $attempt attempts" >&2
  exit 1
}

update_rule "6a680195dc37975e134af4ad" "$host_ip"
update_rule "6a6801a6dc37975e134af4b0" "$host_ip"

if [ -n "$${MINECRAFT_JAVA_RULE_ID:-}" ]; then
  update_rule "$MINECRAFT_JAVA_RULE_ID" "$host_ip"
fi
if [ -n "$${MINECRAFT_BEDROCK_RULE_ID:-}" ]; then
  update_rule "$MINECRAFT_BEDROCK_RULE_ID" "$host_ip"
fi
if [ -n "$${VALHEIM_RULE_ID:-}" ]; then
  update_rule "$VALHEIM_RULE_ID" "$host_ip"
fi

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

      config {
        command = "/bin/sh"
        args = [
          "-c",
          <<-EOT
          set -eu
          data_dir="$NOMAD_ALLOC_DIR/traefik-data"
          mkdir -p "$data_dir"
          if [ ! -s "$data_dir/acme.json" ] && [ -s /Volumes/Cosmonautical/traefik/persistent/acme.json ]; then
            cp -a /Volumes/Cosmonautical/traefik/persistent/. "$data_dir/"
          fi
          chmod 600 "$data_dir/acme.json" 2>/dev/null || true
          EOT
        ]
      }

      resources {
        cpu    = 1
        memory = 16
      }
    }

    task "traefik" {
      driver = "raw_exec"

      template {
        data        = <<EOT
CF_DNS_API_TOKEN={{ key "traefik/CF_DNS_API_TOKEN" }}
EOT
        destination = "secrets/cf.env"
        env         = true
      }

      template {
        data        = <<EOT
entryPoints:
  web:
    address: ":8080"
  websecure:
    address: ":8443"
    transport:
      respondingTimeouts:
        # Default is 1m - too short for large uploads (Nextcloud DAV PUTs
        # in particular) once backend throughput dips under concurrent NAS
        # load. Confirmed 2026-09-25 via a raw curl PUT bypassing every
        # other layer: Traefik's own readTimeout was the actual cause of
        # uploads failing at exactly ~60s, not anything in the Nextcloud
        # job's Caddy/php-fpm config (both already generous, see
        # nextcloud.nomad.hcl).
        readTimeout: 3600s
  traefik:
    address: ":8081"
  postgres:
    address: ":15432"
  minecraft:
    address: ":25565"
  bedrock:
    address: ":19132/udp"
  valheim-game:
    address: ":2456/udp"
  valheim-query:
    address: ":2457/udp"
  valheim-extra:
    address: ":2458/udp"

providers:
  consulCatalog:
    endpoint:
      address: "127.0.0.1:8500"
    exposedByDefault: false
  file:
    filename: "{{ env "NOMAD_ALLOC_DIR" }}/traefik-data/dynamic.yml"

api:
  dashboard: true
  insecure: true

certificatesResolvers:
  cf-dns:
    acme:
      email: violet@cosmonautical.cloud
      storage: {{ env "NOMAD_ALLOC_DIR" }}/traefik-data/acme.json
      dnsChallenge:
        provider: cloudflare
        delayBeforeCheck: 60
        disablePropagationCheck: true
        resolvers:
          - "1.1.1.1:53"
          - "8.8.8.8:53"
EOT
        destination = "local/traefik.yml"
      }

      template {
        data        = <<EOT
#!/bin/sh
set -eu

data_dir="$NOMAD_ALLOC_DIR/traefik-data"

/opt/homebrew/bin/traefik --configfile="$NOMAD_TASK_DIR/traefik.yml" --log.level=INFO &
traefik_pid=$!

sync_loop() {
  while true; do
    sleep 300
    cp "$data_dir/acme.json" /Volumes/Cosmonautical/traefik/persistent/acme.json 2>/dev/null || true
    cp "$data_dir/dynamic.yml" /Volumes/Cosmonautical/traefik/persistent/dynamic.yml 2>/dev/null || true
  done
}
sync_loop &
sync_pid=$!

cleanup() {
  kill "$sync_pid" 2>/dev/null || true
  kill "$traefik_pid" 2>/dev/null || true
  wait "$traefik_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

wait "$traefik_pid"
EOT
        destination = "local/start.sh"
        perms       = "755"
      }

      config {
        command = "${NOMAD_TASK_DIR}/start.sh"
      }

      service {
        name = "traefik"
        port = "dashboard"

        check {
          name     = "tcp"
          type     = "tcp"
          port     = "dashboard"
          interval = "10s"
          timeout  = "2s"
        }
      }

      resources {
        cpu    = 2
        memory = 256
      }
    }
  }
}
