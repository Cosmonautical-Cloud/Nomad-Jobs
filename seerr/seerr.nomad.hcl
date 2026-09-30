job "seerr" {
    datacenters = ["cosmonautical"]
    type        = "service"

    group "seerr" {
        count = 1

        network {
            port "http" {
                static = 5055
            }
    }

        task "seerr" {
            driver = "container"

            config {
                image = "ghcr.io/seerr-team/seerr:v3.4.1"

                ports = ["http"]

                volumes = [
                    "/Volumes/Cosmonautical/seerr/config:/app/config"
                ]
            }

            template {
                data        = <<EOT
DB_TYPE=postgres
DB_HOST={{ range service "postgres" }}{{ .Address }}{{ end }}
DB_PORT={{ range service "postgres" }}{{ .Port }}{{ end }}
DB_USER=seerr
DB_PASS={{ key "seerr/DB_PASSWORD" }}
DB_NAME=seerr
EOT
                destination = "secrets/seerr-db.env"
                env         = true
            }

            service {
                name = "seerr"
                port = "http"

                tags = [
                    "traefik.enable=true",
                    "traefik.http.routers.seerr.rule=Host(`seerr.jellify.app`)",
                    "traefik.http.routers.seerr.entrypoints=websecure",
                    "traefik.http.routers.seerr.tls.certresolver=cf-dns"
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
                cpu    = 2
                memory = 468
            }
    }
    }
}
