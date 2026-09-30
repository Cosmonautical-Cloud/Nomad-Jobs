job "postgres" {
  datacenters = ["cosmonautical"]
  type        = "service"

  group "patroni" {
    count = 3

    constraint {
      distinct_hosts = true
    }

    update {
      health_check      = "task_states"
      min_healthy_time  = "10s"
      healthy_deadline  = "5m"
      progress_deadline = "10m"
    }

    network {
      port "postgres" { static = 5432 }
      port "restapi"  { static = 8008 }
    }

    task "prepare-local-dir" {
      driver = "raw_exec"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      config {
        command = "/bin/sh"
        args    = ["-c", "/bin/mkdir -p /Users/violet/postgres-local/data && /bin/chmod 700 /Users/violet/postgres-local/data"]
      }

      resources {
        cpu    = 1
        memory = 16
      }
    }

    task "patroni" {
      driver = "raw_exec"

      env {
        LC_ALL = "en_US.UTF-8"
      }

      config {
        command = "/Users/violet/patroni-venv/bin/patroni"
        args    = ["${NOMAD_TASK_DIR}/patroni.yml"]
      }

      template {
        data        = <<EOT
scope: postgres-cluster
namespace: /service/
name: {{ env "NOMAD_IP_postgres" }}

restapi:
  listen: 0.0.0.0:8008
  connect_address: {{ env "NOMAD_IP_restapi" }}:8008
  authentication:
    username: patroni
    password: {{ key "postgres/PATRONI_API_PASSWORD" }}

consul:
  host: 127.0.0.1:8500
  register_service: true

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        wal_level: replica
        hot_standby: "on"
        max_wal_senders: 10
        max_replication_slots: 10
        wal_keep_size: 512MB
  initdb:
    - encoding: UTF8
    - data-checksums
  pg_hba:
    - host replication replicator 10.10.37.0/24 md5
    - host replication replicator 127.0.0.1/32 md5
    - host all all 10.10.37.0/24 md5
    - host all all 127.0.0.1/32 md5
    - host all all 192.168.64.0/24 md5
    - host all violet 10.10.20.177/32 md5

postgresql:
  listen: 0.0.0.0:5432
  connect_address: {{ env "NOMAD_IP_postgres" }}:5432
  data_dir: /Users/violet/postgres-local/data
  bin_dir: /opt/homebrew/opt/postgresql@18/bin
  authentication:
    replication:
      username: replicator
      password: {{ key "postgres/REPLICATOR_PASSWORD" }}
    superuser:
      username: violet
      password: {{ key "postgres/PATRONI_SUPERUSER_PASSWORD" }}
    rewind:
      username: violet
      password: {{ key "postgres/PATRONI_SUPERUSER_PASSWORD" }}
  parameters:
    unix_socket_directories: '/tmp'
  pg_hba:
    - host replication replicator 10.10.37.0/24 md5
    - host replication replicator 127.0.0.1/32 md5
    - host all all 10.10.37.0/24 md5
    - host all all 127.0.0.1/32 md5
    - host all all 192.168.64.0/24 md5
    - host all violet 10.10.20.177/32 md5

tags:
  nofailover: false
  noloadbalance: false
  clonefrom: true
  nosync: false
EOT
        destination = "local/patroni.yml"
      }

      service {
        name = "postgres"
        port = "postgres"

        # Routed through Traefik's dedicated :15432 postgres entrypoint (see
        # traefik.nomad). Only this service - gated by the /primary check
        # below, which patroni only answers 200 on the current leader - is
        # tagged for Traefik; postgres-node below isn't, since it's healthy
        # on every replica and would let Traefik load-balance writes across
        # nodes that aren't the primary.
        tags = [
          "traefik.enable=true",
          "traefik.tcp.routers.postgres.rule=HostSNI(`*`)",
          "traefik.tcp.routers.postgres.entrypoints=postgres",
          "traefik.tcp.services.postgres.loadbalancer.server.port=5432",
        ]

        check {
          name     = "primary"
          type     = "http"
          path     = "/primary"
          port     = "restapi"
          interval = "5s"
          timeout  = "3s"
        }
      }

      service {
        name = "postgres-node"
        port = "postgres"

        check {
          name     = "health"
          type     = "http"
          path     = "/health"
          port     = "restapi"
          interval = "10s"
          timeout  = "3s"
        }
      }

      resources {
        cpu    = 2
        memory = 1024
      }
    }
  }
}
