job "radarr" {
  datacenters = ["cosmonautical"]
  type        = "service"
  priority = 60

  group "radarr" {
    count = 1

    network {
      port "http" { static = 7878 }
    }

    task "radarr" {
      driver = "raw_exec"

      config {
        command = "/Applications/Radarr.app/Contents/MacOS/radarr"
      }

      service {
        name = "radarr"
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
        memory = 512
      }
    }
  }
}

