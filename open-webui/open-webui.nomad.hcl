job "open-webui" {
  datacenters = ["cosmonautical"]
  type        = "service"

  constraint {
    attribute = "${attr.unique.hostname}"
    value     = "taurus.cosmonautical.cloud"
  }

  group "ui" {
    count = 1

    network {
      port "ui" { static = 8082 }
    }

    task "open-webui" {
      driver = "raw_exec"

      env {
        OLLAMA_BASE_URL = "http://ollama.service.consul:11434"

        WEBUI_URL           = "https://ai.jellify.app"
        ENABLE_LOGIN_FORM   = "false"

        ENABLE_OAUTH_SIGNUP           = "true"
        OAUTH_MERGE_ACCOUNTS_BY_EMAIL = "true"
        OAUTH_CLIENT_ID               = "open-webui"
        OAUTH_PROVIDER_NAME           = "Cosmonautical"
        OPENID_PROVIDER_URL           = "https://auth.cosmonautical.cloud/realms/cosmonautical/.well-known/openid-configuration"
        OPENID_REDIRECT_URI           = "https://ai.jellify.app/oauth/oidc/callback"
      }

      template {
        data        = <<EOT
OAUTH_CLIENT_SECRET={{ key "open-webui/OAUTH_CLIENT_SECRET" }}
WEBUI_SECRET_KEY={{ key "open-webui/WEBUI_SECRET_KEY" }}
DATABASE_URL=postgresql+psycopg://openwebui:{{ key "open-webui/DB_PASSWORD" }}@{{ range service "postgres" }}{{ .Address }}:{{ .Port }}{{ end }}/openwebui
EOT
        destination = "secrets/oauth.env"
        env         = true
      }

      config {
        command = "/opt/homebrew/Caskroom/miniconda/base/envs/open-webui/bin/open-webui"
        args = [
          "serve",
          "--port=8082"
        ]
      }

      service {
        name = "open-webui"
        port = "ui"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.open-webui.rule=Host(`ai.jellify.app`)",
          "traefik.http.routers.open-webui.entrypoints=websecure",
          "traefik.http.routers.open-webui.tls.certresolver=cf-dns"
        ]

        check {
          name     = "tcp"
          type     = "tcp"
          port     = "ui"
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

