job "seaweedfs-nfs-backup" {
  datacenters = ["cosmonautical"]
  type        = "service"

  group "backup" {
    count = 1

    constraint {
      attribute = "${attr.unique.hostname}"
      value     = "cassiopeia.cosmonautical.cloud"
    }

    task "backup-to-share" {
      driver = "raw_exec"

      config {
        command = "/bin/sh"
        args = [
          "-c",
          <<-EOT
          /bin/mkdir -p /Volumes/Cosmonautical/seaweedfs-backup/data
          test -w /Volumes/Cosmonautical/seaweedfs-backup/data
          cd "${NOMAD_TASK_DIR}"
          exec /opt/homebrew/bin/weed filer.backup \
            -filer=seaweedfs-filer.service.consul:8888 \
            -filerPath=/ \
            -filerExcludePaths=/sabnzbd,/lidarr/config \
            -disableErrorRetry \
            -filerProxy
          EOT
        ]
      }

      template {
        data = <<EOT
[sink.local]
enabled = true
directory = "/Volumes/Cosmonautical/seaweedfs-backup/data"
is_incremental = true
EOT
        destination = "local/replication.toml"
      }

      resources {
        cpu    = 1
        memory = 1024
      }
    }
  }
}