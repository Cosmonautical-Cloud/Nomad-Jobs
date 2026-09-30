job "audiomuse-ai" {
  datacenters = ["cosmonautical"]
  type        = "service"

  group "audiomuse-ai" {
    count = 1

    network {
      port "http" {
        static = 8000
      }
    }

    task "audiomuse-ai" {
      driver = "raw_exec"

      config {
        command = "/Applications/AudioMuse-AI.app/Contents/MacOS/AudioMuse-AI"
        args    = []
      }

      template {
        data        = <<EOT
POSTGRES_HOST={{ range service "postgres" }}{{ .Address }}{{ end }}
POSTGRES_PORT={{ range service "postgres" }}{{ .Port }}{{ end }}
POSTGRES_DB=audiomuse
POSTGRES_USER=audiomuse
POSTGRES_PASSWORD={{ key "audiomuse/DB_PASSWORD" }}
DATABASE_URL=postgresql://audiomuse:{{ key "audiomuse/DB_PASSWORD" }}@{{ range service "postgres" }}{{ .Address }}:{{ .Port }}{{ end }}/audiomuse
PGHOST={{ range service "postgres" }}{{ .Address }}{{ end }}
PGPORT={{ range service "postgres" }}{{ .Port }}{{ end }}
PGUSER=audiomuse
PGPASSWORD={{ key "audiomuse/DB_PASSWORD" }}
PGDATABASE=audiomuse
REDIS_HOST={{ range service "redis" }}{{ .Address }}{{ end }}
REDIS_PORT={{ range service "redis" }}{{ .Port }}{{ end }}
REDIS_DB=2
REDIS_PASSWORD={{ key "redis/PASSWORD" }}
REDIS_URL=redis://:{{ key "redis/PASSWORD" }}@{{ range service "redis" }}{{ .Address }}:{{ .Port }}{{ end }}/2
EOT
        destination = "secrets/audiomuse.env"
        env         = true
      }

      service {
        name = "audiomuse-ai"
        port = "http"

        check {
          type     = "tcp"
          port     = "http"
          interval = "60s"
          timeout  = "15s"
        }
      }

      constraint {
        attribute = "${attr.consul.version}"
        operator  = ">="
        value     = "1.8.0"
      }

      resources {
        cpu        = 6
        memory     = 6144
      }

      kill_timeout = "5s"
    }
  }
}
