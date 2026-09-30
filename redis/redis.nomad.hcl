job "redis" {
  datacenters = ["cosmonautical"]
  type        = "service"

  update {
    health_check = "task_states"
  }

  group "primary" {
    count = 1

    constraint {
      attribute = "${attr.unique.hostname}"
      value     = "taurus.cosmonautical.cloud"
    }

    network {
      port "cache" { static = 6379 }
    }

    task "redis" {
      driver = "raw_exec"

      config {
        command = "/opt/homebrew/bin/redis-server"
        args    = ["${NOMAD_TASK_DIR}/redis.conf"]
      }

      template {
        data        = <<EOT
port 6379
bind 0.0.0.0
protected-mode yes
requirepass {{ key "redis/PASSWORD" }}
masterauth {{ key "redis/PASSWORD" }}
dir /Volumes/Cosmonautical/seaweedfs-filer-redis
save 300 10
save 60 1000
stop-writes-on-bgsave-error no
EOT
        destination = "local/redis.conf"
      }

      service {
        name = "redis-node"
        port = "cache"
        tags = ["primary-group"]

        check {
          name     = "tcp"
          type     = "tcp"
          port     = "cache"
          interval = "10s"
          timeout  = "2s"
        }
      }

      service {
        name = "redis"
        port = "cache"

        check {
          name     = "current-master"
          type     = "script"
          command  = "/bin/sh"
          args     = ["-c", "[ \"$(/opt/homebrew/bin/redis-cli -p 26379 -h 127.0.0.1 SENTINEL get-master-addr-by-name master 2>/dev/null | head -1)\" = \"$NOMAD_IP_cache\" ] || exit 2"]
          interval = "10s"
          timeout  = "5s"
        }
      }

      resources {
        cpu    = 1
        memory = 256
      }
    }
  }

  group "replica" {
    count = 2

    constraint {
      distinct_hosts = true
    }
    constraint {
      attribute = "${attr.unique.hostname}"
      operator  = "!="
      value     = "taurus.cosmonautical.cloud"
    }

    network {
      port "cache" { static = 6379 }
    }

    task "prepare-local-dir" {
      driver = "raw_exec"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      config {
        command = "/bin/mkdir"
        args    = ["-p", "/opt/seaweedfs/redis-local/data"]
      }

      resources {
        cpu    = 1
        memory = 16
      }
    }

    task "redis" {
      driver = "raw_exec"

      config {
        command = "/opt/homebrew/bin/redis-server"
        args    = ["${NOMAD_TASK_DIR}/redis.conf"]
      }

      template {
        data        = <<EOT
port 6379
bind 0.0.0.0
protected-mode yes
requirepass {{ key "redis/PASSWORD" }}
masterauth {{ key "redis/PASSWORD" }}
dir /opt/seaweedfs/redis-local/data
replicaof taurus.cosmonautical.cloud 6379
EOT
        destination = "local/redis.conf"
      }

      service {
        name = "redis-node"
        port = "cache"
        tags = ["replica-group"]

        check {
          name     = "tcp"
          type     = "tcp"
          port     = "cache"
          interval = "10s"
          timeout  = "2s"
        }
      }

      service {
        name = "redis"
        port = "cache"

        check {
          name     = "current-master"
          type     = "script"
          command  = "/bin/sh"
          args     = ["-c", "[ \"$(/opt/homebrew/bin/redis-cli -p 26379 -h 127.0.0.1 SENTINEL get-master-addr-by-name master 2>/dev/null | head -1)\" = \"$NOMAD_IP_cache\" ] || exit 2"]
          interval = "10s"
          timeout  = "5s"
        }
      }

      resources {
        cpu    = 1
        memory = 256
      }
    }
  }

  group "sentinel" {
    count = 3

    constraint {
      distinct_hosts = true
    }

    network {
      port "sentinel" { static = 26379 }
    }

    task "sentinel" {
      driver = "raw_exec"

      config {
        command = "/opt/homebrew/bin/redis-sentinel"
        args    = ["${NOMAD_TASK_DIR}/sentinel.conf"]
      }

      template {
        data        = <<EOT
port 26379
resolve-hostnames yes
announce-hostnames yes
sentinel resolve-hostnames yes
sentinel monitor master taurus.cosmonautical.cloud 6379 2
sentinel auth-pass master {{ key "redis/PASSWORD" }}
sentinel down-after-milliseconds master 5000
sentinel failover-timeout master 60000
sentinel parallel-syncs master 1
EOT
        destination = "local/sentinel.conf"
      }

      service {
        name = "redis-sentinel"
        port = "sentinel"

        check {
          name     = "tcp"
          type     = "tcp"
          port     = "sentinel"
          interval = "10s"
          timeout  = "2s"
        }
      }

      resources {
        cpu    = 1
        memory = 64
      }
    }
  }
}
