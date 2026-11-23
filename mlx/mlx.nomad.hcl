job "mlx" {
  datacenters = ["cosmonautical"]
  type        = "service"

  # One model split across taurus (rank 0, serves the API) and orion
  # (rank 1) over a Thunderbolt 5 cable, with MLX's jaccl backend (RDMA).
  # The link addresses come from Nomadintosh's thunderbolt_link role, and the
  # rdma_enN names in each ibv_devices.json must match its interfaces.

  group "rank0" {
    count = 1

    constraint {
      attribute = "${attr.unique.hostname}"
      value     = "taurus.cosmonautical.cloud"
    }

    network {
      port "api" { static = 11435 }
      port "coordinator" { static = 11436 }
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

      template {
        destination = "local/ibv_devices.json"
        data        = <<-EOT
        [[null, "rdma_en2"], ["rdma_en2", null]]
        EOT
      }

      env {
        HOME                  = "/Users/violet"
        HF_HOME               = "/Volumes/WD Black/huggingface"
        MLX_RANK              = "0"
        MLX_JACCL_COORDINATOR = "172.31.250.1:${NOMAD_PORT_coordinator}"
        MLX_IBV_DEVICES       = "${NOMAD_TASK_DIR}/ibv_devices.json"
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

          check_restart {
            limit = 2
            grace = "2m"
          }
        }
      }

      resources {
        cpu    = 4
        memory = 8192
      }

      kill_timeout = "10s"
    }
  }

  group "rank1" {
    count = 1

    constraint {
      attribute = "${attr.unique.hostname}"
      value     = "orion.cosmonautical.cloud"
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
        HF_HOME = "/Users/violet/.cache/huggingface"
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

      template {
        destination = "local/ibv_devices.json"
        data        = <<-EOT
        [[null, "rdma_en2"], ["rdma_en2", null]]
        EOT
      }

      env {
        HOME                  = "/Users/violet"
        HF_HOME               = "/Users/violet/.cache/huggingface"
        MLX_RANK              = "1"
        MLX_JACCL_COORDINATOR = "172.31.250.1:11436"
        MLX_IBV_DEVICES       = "${NOMAD_TASK_DIR}/ibv_devices.json"
      }

      # No HTTP server on rank 1: it only takes rank 0's requests. If rank 0
      # goes away, its collectives should fail and the process exit, so Nomad
      # restarts it until rank 0 is back.
      config {
        command = "${NOMAD_ALLOC_DIR}/venv/bin/mlx_lm.server"
        args = [
          "--max-tokens=8192",
        ]
      }

      restart {
        attempts = 10
        interval = "30m"
        delay    = "15s"
        mode     = "delay"
      }

      resources {
        cpu = 4
        # Nomad has ~2.5 GB of orion left to hand out. raw_exec memory isn't
        # enforced on macOS, and orion has ~15 GB actually free.
        memory = 2048
      }

      kill_timeout = "10s"
    }
  }
}
