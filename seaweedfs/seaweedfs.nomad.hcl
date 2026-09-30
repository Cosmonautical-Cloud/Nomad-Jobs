job "seaweedfs" {
  datacenters = ["cosmonautical"]
  type        = "system"

  update {
    max_parallel     = 1
    min_healthy_time = "15s"
  }

  group "masters" {
    network {
      port "http" { static = 9333 }
      port "grpc" { static = 19333 }
    }

    service {
      name     = "seaweedfs-master"
      port     = "http"
      provider = "consul"

      check {
        type     = "http"
        path     = "/cluster/status"
        interval = "10s"
        timeout  = "2s"
      }
    }

    task "master" {
      driver = "raw_exec"

      config {
        command = "/opt/homebrew/bin/weed"
        args = [
          "master",
          "-ip=${attr.unique.hostname}",
          "-port=9333",
          "-port.grpc=19333",
          "-peers=cassiopeia.cosmonautical.cloud:9333,taurus.cosmonautical.cloud:9333,betelgeuse.cosmonautical.cloud:9333",
          "-mdir=/opt/seaweedfs/master",
          "-volumeSizeLimitMB=1024",
          "-defaultReplication=001"
        ]
      }

      resources {
        cpu    = 2
        memory = 512
      }
    }
  }

  group "volume-nodes" {
    network {
      port "http" { static = 8080 }
      port "grpc" { static = 18080 }
    }

    task "volume" {
      driver = "raw_exec"

      config {
        command = "/opt/homebrew/bin/weed"
        args = [
          "volume",
          "-ip=${NOMAD_IP_http}",
          "-port=8080",
          "-port.grpc=18080",
          "-mserver=cassiopeia.cosmonautical.cloud:9333,taurus.cosmonautical.cloud:9333,betelgeuse.cosmonautical.cloud:9333",
          "-dir=/opt/seaweedfs/data",
          "-max=0"
        ]
      }

      resources {
        cpu    = 2
        memory = 1024
      }
    }
  }
}
