job "keycloak" {
  datacenters = ["cosmonautical"]
  type        = "service"

  group "keycloak" {
    count = 1

    restart {
      attempts = 10
      interval = "30m"
      delay    = "15s"
      mode     = "delay"
    }

    network {
      port "http"       { static = 8180 }
      port "management" { static = 9000 }
    }

    service {
      name     = "keycloak"
      port     = "http"

      check {
        type     = "http"
        port     = "management"
        path     = "/health/ready"
        interval = "10s"
        timeout  = "2s"
      }

        tags = [
            "traefik.enable=true",
            "traefik.http.routers.keycloak.rule=Host(`auth.cosmonautical.cloud`)",
            "traefik.http.routers.keycloak.entrypoints=websecure",
            "traefik.http.routers.keycloak.tls.certresolver=cf-dns",
            "traefik.http.routers.keycloak.middlewares=keycloak-default-realm",
            "traefik.http.middlewares.keycloak-default-realm.redirectregex.regex=^https://auth\\.cosmonautical\\.cloud/?$",
            "traefik.http.middlewares.keycloak-default-realm.redirectregex.replacement=https://auth.cosmonautical.cloud/realms/cosmonautical/account/",
            "traefik.http.middlewares.keycloak-default-realm.redirectregex.permanent=true"
        ]
    }

    task "keycloak" {
      driver = "raw_exec"

      artifact {
        source      = "https://github.com/keycloak/keycloak/releases/download/26.7.3/keycloak-26.7.3.tar.gz"
        destination = "local/"
        options {
          checksum = "sha256:77657f30b7e90d70f727712ce1c967f430fd6a5e9f458d32d8c6df0635345f47"
        }
      }

      config {
        command = "${NOMAD_TASK_DIR}/keycloak-26.7.3/bin/kc.sh"
        args = [
          "start",
          "--http-port=8180",
          "--hostname-strict=false",
          "--http-enabled=true",
          "--hostname=https://auth.cosmonautical.cloud",
          "--proxy-headers=xforwarded",
          "--http-management-port=9000"
        ]
      }

      env {
        KEYCLOAK_ADMIN          = "admin"
        KC_DB                   = "postgres"
        KC_DB_URL               = "jdbc:postgresql://postgres.service.consul:5432/keycloak"
        KC_DB_USERNAME          = "keycloak"
        KC_HEALTH_ENABLED       = "true"
        JAVA_HOME               = "/opt/homebrew/opt/openjdk"
        PATH                    = "/opt/homebrew/bin:/opt/homebrew/opt/openjdk/bin:/usr/bin:/bin:/usr/sbin:/sbin"
      }

      template {
        data        = <<EOT
KC_DB_PASSWORD={{ key "keycloak/DB_PASSWORD" }}
KEYCLOAK_ADMIN_PASSWORD={{ key "keycloak/BOOTSTRAP_ADMIN_PASSWORD" }}
EOT
        destination = "secrets/db.env"
        env         = true
      }

      resources {
        cpu    = 2
        memory = 1024
      }
    }
  }
}
