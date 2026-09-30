job "dispatcharr" {
  datacenters = ["cosmonautical"]
  type        = "service"

  group "server" {
    count = 1

    constraint {
      attribute = "${attr.unique.hostname}"
      value     = "betelgeuse.cosmonautical.cloud"
    }

    network {
      port "http" {
        static = 9191
      }
    }

    task "dispatcharr" {
      driver = "container"

      config {
        image = "ghcr.io/dispatcharr/dispatcharr:0.31.0-arm64"

        ports = ["http"]

        volumes = [
          "/Users/violet/dispatcharr-local/data:/data",
          "/Volumes/Cosmonautical/dispatcharr-backups:/data/backups",
          "/Volumes/Cosmonautical/dispatcharr-recordings:/data/recordings",
          "/Volumes/Cosmonautical/dispatcharr-uploads:/data/uploads",
          "/Volumes/Cosmonautical/dispatcharr-plugins:/data/plugins"
        ]
      }

      env {
        DISPATCHARR_ENV       = "modular"
        POSTGRES_HOST         = "postgres.service.consul"
        POSTGRES_PORT         = "5432"
        POSTGRES_DB           = "dispatcharr"
        POSTGRES_USER         = "dispatcharr"
        REDIS_HOST            = "redis.service.consul"
        REDIS_PORT            = "6379"
        DISPATCHARR_LOG_LEVEL = "info"
        DISPATCHARR_LOG_DIR = "/tmp/dispatcharr-logs"
        PUID = "1000"
        PGID = "1000"
      }

      template {
        data        = <<EOT
POSTGRES_PASSWORD={{ key "dispatcharr/DB_PASSWORD" }}
REDIS_PASSWORD={{ key "redis/PASSWORD" }}
EOT
        destination = "secrets/db.env"
        env         = true
      }

      service {
				name = "dispatcharr"
        port = "http"
        check {
          name     = "tcp"
          type     = "tcp"
          port     = "http"
          interval = "60s"
          timeout  = "15s"
        }
      }

      resources {
        cpu    = 4
        memory = 2048
      }
    }

    task "celery" {
      driver = "container"

      config {
        image = "ghcr.io/dispatcharr/dispatcharr:0.31.0-arm64"

        entrypoint = "/app/docker/entrypoint.celery.sh"

        volumes = [
          "/Users/violet/dispatcharr-local/data:/data",
          "/Volumes/Cosmonautical/dispatcharr-backups:/data/backups",
          "/Volumes/Cosmonautical/dispatcharr-recordings:/data/recordings",
          "/Volumes/Cosmonautical/dispatcharr-uploads:/data/uploads",
          "/Volumes/Cosmonautical/dispatcharr-plugins:/data/plugins"
        ]
      }

      env {
        DISPATCHARR_ENV       = "modular"
        POSTGRES_HOST         = "postgres.service.consul"
        POSTGRES_PORT         = "5432"
        POSTGRES_DB           = "dispatcharr"
        POSTGRES_USER         = "dispatcharr"
        REDIS_HOST            = "redis.service.consul"
        REDIS_PORT            = "6379"
        DISPATCHARR_WEB_HOST  = "dispatcharr.service.consul"
        DISPATCHARR_PORT      = "9191"
        DISPATCHARR_LOG_LEVEL = "info"
        DISPATCHARR_LOG_DIR = "/tmp/dispatcharr-logs"
        CELERY_MAX_WORKERS = "2"
        CELERY_MIN_WORKERS = "1"
        PUID = "1000"
        PGID = "1000"
      }

      template {
        data        = <<EOT
POSTGRES_PASSWORD={{ key "dispatcharr/DB_PASSWORD" }}
REDIS_PASSWORD={{ key "redis/PASSWORD" }}
EOT
        destination = "secrets/db.env"
        env         = true
      }

      resources {
        cpu    = 2
        memory = 2048
      }
    }
  }
}
