job "sonarr" {
  datacenters = ["cosmonautical"]
  type        = "service"
  priority = 60

  group "sonarr" {
    count = 1

    network {
      port "http" { static = 8989 }
    }

    task "sonarr" {
      driver = "raw_exec"

      config {
        command = "/Applications/Sonarr.app/Contents/MacOS/sonarr"
      }

      service {
        name = "sonarr"
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

