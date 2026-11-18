job "seaweedfs-filer" {
  datacenters = ["cosmonautical"]
  type        = "service"

  group "filer" {
    count = 1

    network {
      port "http" { static = 8888 }
      port "grpc" { static = 18888 }
      port "s3"   { static = 8333 }
    }

    service {
      name     = "seaweedfs-filer"
      port     = "http"
      provider = "consul"

      check {
        type     = "http"
        path     = "/"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "filer" {
      driver = "raw_exec"

      template {
        data        = <<EOT
[redis2_sentinel]
enabled = true
addresses = [{{ range service "redis-sentinel" }}"{{ .Address }}:{{ .Port }}",{{ end }}]
masterName = "master"
username = ""
password = "{{ key "redis/PASSWORD" }}"
database = 1
keyPrefix = ""
enable_tls = false

[leveldb2]
enabled = false
EOT
        destination = "filer.toml"
      }

      config {
        command = "/opt/homebrew/bin/weed"
        args = [
          "filer",
          "-ip=${attr.unique.hostname}",
          "-port=8888",
          "-port.grpc=18888",
          "-master=cassiopeia.cosmonautical.cloud:9333,taurus.cosmonautical.cloud:9333,betelgeuse.cosmonautical.cloud:9333",
          "-defaultReplicaPlacement=001"
        ]
      }

      resources {
        cpu    = 4
        memory = 1024
      }
    }

    task "s3" {
      driver = "raw_exec"

      template {
        data        = <<EOT
{
  "identities": [
    {
      "name": "litestream",
      "credentials": [
        {
          "accessKey": "{{ key "seaweedfs-s3/ACCESS_KEY" }}",
          "secretKey": "{{ key "seaweedfs-s3/SECRET_KEY" }}"
        }
      ],
      "actions": ["Read", "Write", "List", "Tagging", "Admin"]
    }
  ]
}
EOT
        destination = "secrets/s3-identities.json"
      }

      config {
        command = "/opt/homebrew/bin/weed"
        args = [
          "s3",
          "-filer=127.0.0.1:8888",
          "-port=8333",
          "-config=${NOMAD_SECRETS_DIR}/s3-identities.json"
        ]
      }

      service {
        name = "seaweedfs-s3"
        port = "s3"

        check {
          name     = "tcp"
          type     = "tcp"
          port     = "s3"
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
