job "open-webui" {
  datacenters = ["cosmonautical"]
  type        = "service"

  group "ui" {
    count = 1

    ephemeral_disk {
      size    = 6000
      migrate = true
      sticky  = true
    }

    network {
      port "ui" { static = 8082 }
    }

    task "install" {
      driver = "raw_exec"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      artifact {
        source      = "https://files.pythonhosted.org/packages/py3/u/uv/uv-0.13.9-py3-none-macosx_11_0_arm64.whl"
        destination = "local/uv"

        options {
          archive  = "zip"
          checksum = "sha256:66c512266d633bef48384a1f53003f41f2a8e7b36fe6e7fbfd3e0fd52d96fa63"
        }
      }

      artifact {
        source      = "https://files.pythonhosted.org/packages/py3/o/open-webui/open_webui-0.13.4-py3-none-any.whl"
        destination = "local/wheels"

        options {
          checksum = "sha256:8cabd1c68c8dde3b88c49223b45c68fdfdc428d00239056303a007bd334b62dd"
        }
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
          uv=$(echo "$NOMAD_TASK_DIR"/uv/uv-*.data/scripts/uv)
          chmod +x "$uv"
          venv="$NOMAD_ALLOC_DIR/venv"
          if [ ! -e "$venv/.installed" ]; then
            "$uv" venv --clear --managed-python --python 3.12 "$venv"
            "$uv" pip install --python "$venv/bin/python" "$NOMAD_TASK_DIR"/wheels/*.whl
            touch "$venv/.installed"
          fi
          mkdir -p "$NOMAD_ALLOC_DIR/data/open-webui"
          EOT
        ]
      }

      resources {
        cpu    = 1
        memory = 1024
      }
    }

    task "ensure-bucket" {
      driver = "raw_exec"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      template {
        data        = <<EOT
#!/bin/sh
set -eu
if ! out=$(printf 's3.bucket.create -name open-webui\nexit\n' | /opt/homebrew/bin/weed shell -filer={{ range service "seaweedfs-filer" }}{{ .Address }}:{{ .Port }}{{ end }} 2>&1); then
  case "$out" in
    *"already exists"*) ;;
    *) echo "$out" >&2; exit 1 ;;
  esac
fi
echo "$out"
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

    task "open-webui" {
      driver = "raw_exec"

      env {
        HOME     = "/Users/violet"
        DATA_DIR = "${NOMAD_ALLOC_DIR}/data/open-webui"

        STORAGE_PROVIDER    = "s3"
        S3_BUCKET_NAME      = "open-webui"
        S3_REGION_NAME      = "us-east-1"
        S3_ADDRESSING_STYLE = "path"

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
S3_ENDPOINT_URL=http://{{ range service "seaweedfs-s3" }}{{ .Address }}:{{ .Port }}{{ end }}
S3_ACCESS_KEY_ID={{ key "seaweedfs-s3/ACCESS_KEY" }}
S3_SECRET_ACCESS_KEY={{ key "seaweedfs-s3/SECRET_KEY" }}
EOT
        destination = "secrets/oauth.env"
        env         = true
      }

      config {
        command = "${NOMAD_ALLOC_DIR}/venv/bin/open-webui"
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
        memory = 1024
      }
    }
  }
}
