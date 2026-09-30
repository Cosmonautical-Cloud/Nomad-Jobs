job "jellyfin" {
  datacenters = ["cosmonautical"]
  type        = "service"
  priority = 60

  constraint {
    attribute = "${attr.unique.hostname}"
    value     = "cassiopeia.cosmonautical.cloud"
  }

  group "jellyfin" {
    count = 1

    network {
      port "http" { static = 8096 }
    }

    task "jellyfin" {
      driver = "raw_exec"

      config {
        command = "/Applications/Jellyfin.app/Contents/MacOS/jellyfin"
        args = [
          "--webdir", "/Applications/Jellyfin.app/Contents/Resources/jellyfin-web/"
        ]
      }

      service {
        name = "jellyfin"
        port = "http"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.jellyfin.rule=Host(`jellyfin.jellify.app`)",
          "traefik.http.routers.jellyfin.entrypoints=websecure",
          "traefik.http.routers.jellyfin.tls.certresolver=cf-dns"
        ]

        check {
          name     = "tcp"
          type     = "tcp"
          port     = "http"
          interval = "60s"
          timeout  = "15s"
        }
      }

      resources {
        cpu    = 10
        memory = 4096
      }
    }
  }
}


