job "deemix" {
  datacenters = ["cosmonautical"]
  type        = "service"

  group "deemix" {
    count = 1

    network {
      port "http" {
        static = 6595
        to     = 6595
      }
    }

    task "deemix" {
      driver = "container"

      config {
        image = "ghcr.io/bambanah/deemix:latest"
        ports = ["http"]

        volumes = [
          "/Volumes/Cosmonautical/deemix/config:/config",
          "/Volumes/Cosmonautical/deemix/downloads:/downloads",
        ]

        env = {
          DEEMIX_SERVER_PORT = "6595"
          DEEMIX_DATA_DIR     = "/config"
          DEEMIX_MUSIC_DIR    = "/downloads"
          DEEMIX_HOST         = "0.0.0.0"
          DEEMIX_SINGLE_USER  = "true"
          PUID                = "501"
          PGID                = "20"
        }

        labels = {
          "app" = "deemix"
        }
      }

      service {
        name = "deemix"
        port = "http"

        check {
          name     = "tcp"
          type     = "tcp"
          port     = "http"
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
