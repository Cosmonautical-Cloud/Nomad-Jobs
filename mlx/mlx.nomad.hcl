job "mlx" {
  datacenters = ["cosmonautical"]
  type        = "service"

  group "mlx" {
    count = 1

    constraint {
      attribute = "${attr.unique.hostname}"
      value     = "taurus.cosmonautical.cloud"
    }

    network {
      port "api" { static = 11435 }
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
        source      = "https://files.pythonhosted.org/packages/py3/m/mlx-lm/mlx_lm-0.32.2-py3-none-any.whl"
        destination = "local/wheels"

        options {
          checksum = "sha256:5c0991248cfff5872503d74f466d2532dd8cb7fb3670cb9be7a06d7305dadc04"
        }
      }

      env {
        HOME    = "/Users/violet"
        HF_HOME = "/Volumes/WD Black/huggingface"
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
          mkdir -p "$HF_HOME/hub"
          EOT
        ]
      }

      resources {
        cpu    = 1
        memory = 512
      }
    }

    task "mlx" {
      driver = "raw_exec"

      env {
        HOME    = "/Users/violet"
        HF_HOME = "/Volumes/WD Black/huggingface"
      }

      config {
        command = "${NOMAD_ALLOC_DIR}/venv/bin/mlx_lm.server"
        args = [
          "--host=0.0.0.0",
          "--port=${NOMAD_PORT_api}",
          "--max-tokens=8192",
        ]
      }

      service {
        name = "mlx"
        port = "api"

        check {
          type     = "http"
          path     = "/health"
          port     = "api"
          interval = "30s"
          timeout  = "5s"
        }
      }

      resources {
        cpu    = 4
        memory = 8192
      }

      kill_timeout = "10s"
    }

    task "fetch-models" {
      driver = "raw_exec"

      lifecycle {
        hook    = "poststart"
        sidecar = false
      }

      env {
        HOME    = "/Users/violet"
        HF_HOME = "/Volumes/WD Black/huggingface"
        MODELS  = "mlx-community/Qwen3.5-9B-4bit mlx-community/gemma-4-e4b-it-4bit"
      }

      config {
        command = "/bin/sh"
        args = [
          "-c",
          <<-EOT
          set -eu
          for model in $MODELS; do
            "$NOMAD_ALLOC_DIR/venv/bin/hf" download "$model"
          done
          EOT
        ]
      }

      resources {
        cpu    = 1
        memory = 256
      }
    }
  }
}
