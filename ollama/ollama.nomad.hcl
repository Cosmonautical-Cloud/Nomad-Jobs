job "ollama" {
  datacenters = ["cosmonautical"]
  type        = "service"

  constraint {
    attribute = "${attr.unique.hostname}"
    value     = "taurus.cosmonautical.cloud"
  }

  group "ollama" {
    count = 1

    network {
      port "api" {
        static = 11434
      }
    }

    task "ollama" {
      driver = "raw_exec"

      env {
        OLLAMA_HOST   = "0.0.0.0:11434"
        OLLAMA_MODELS = "/Volumes/WD Black/ollama-models"
      }

      config {
        command = "/opt/homebrew/opt/ollama/bin/ollama"
        args    = ["serve"]
      }

      service {
        name = "ollama"
        port = "api"

        check {
          type     = "tcp"
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
  }
}
