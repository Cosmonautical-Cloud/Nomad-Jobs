resource "nomad_job" "nextcloud" {
  jobspec = file("${path.module}/nextcloud/nextcloud.nomad.hcl")
}

resource "nomad_job" "nextcloud-cron" {
  jobspec = file("${path.module}/nextcloud/nextcloud-cron.nomad.hcl")
}

resource "nomad_job" "nextcloud-preview-generate" {
  jobspec = file("${path.module}/nextcloud/nextcloud-preview-generate.nomad.hcl")
}

resource "nomad_job" "nextcloud-s3-backup" {
  jobspec = file("${path.module}/nextcloud/nextcloud-s3-backup.nomad.hcl")
}

resource "nomad_job" "nextcloud-roms-scan" {
  jobspec = file("${path.module}/nextcloud/nextcloud-roms-scan.nomad.hcl")
}

resource "nomad_job" "postgres" {
  jobspec = file("${path.module}/postgres/postgres.nomad.hcl")
}

resource "nomad_job" "postgres-backup" {
  jobspec = file("${path.module}/postgres/postgres-backup.nomad.hcl")
}

resource "nomad_job" "redis" {
  jobspec = file("${path.module}/redis/redis.nomad.hcl")
}

resource "nomad_job" "traefik" {
  jobspec = file("${path.module}/traefik/traefik.nomad.hcl")
}

resource "nomad_job" "seaweedfs" {
  jobspec = file("${path.module}/seaweedfs/seaweedfs.nomad.hcl")
}

resource "nomad_job" "seaweedfs-filer" {
  jobspec = file("${path.module}/seaweedfs/seaweedfs-filer.nomad.hcl")
}

resource "nomad_job" "seaweedfs-nfs-backup" {
  jobspec = file("${path.module}/seaweedfs/seaweedfs-nfs-backup.nomad.hcl")
}

resource "nomad_job" "audiomuse-ai" {
  jobspec = file("${path.module}/audiomuse-ai/audiomuse-ai.nomad.hcl")
}

resource "nomad_job" "openldap" {
  jobspec = file("${path.module}/openldap/openldap.nomad.hcl")
}

resource "nomad_job" "deemix" {
  jobspec = file("${path.module}/deemix/deemix.nomad.hcl")
}

resource "nomad_job" "dispatcharr" {
  jobspec = file("${path.module}/dispatcharr/dispatcharr.nomad.hcl")
}

resource "nomad_job" "home-assistant" {
  jobspec = file("${path.module}/home-assistant/home-assistant.nomad.hcl")
}

resource "nomad_job" "jellyfin" {
  jobspec = file("${path.module}/jellyfin/jellyfin.nomad.hcl")
}

resource "nomad_job" "keycloak" {
  jobspec = file("${path.module}/keycloak/keycloak.nomad.hcl")
}

resource "nomad_job" "lidarr" {
  jobspec = file("${path.module}/lidarr/lidarr.nomad.hcl")
}

resource "nomad_job" "ollama" {
  jobspec = file("${path.module}/ollama/ollama.nomad.hcl")
}

resource "nomad_job" "open-webui" {
  jobspec = file("${path.module}/open-webui/open-webui.nomad.hcl")
}

resource "nomad_job" "radarr" {
  jobspec = file("${path.module}/radarr/radarr.nomad.hcl")
}

resource "nomad_job" "romm" {
  jobspec = file("${path.module}/romm/romm.nomad.hcl")
}

resource "nomad_job" "sabnzbd" {
  jobspec = file("${path.module}/sabnzbd/sabnzbd.nomad.hcl")
}

resource "nomad_job" "seerr" {
  jobspec = file("${path.module}/seerr/seerr.nomad.hcl")
}

resource "nomad_job" "semaphore" {
  jobspec = file("${path.module}/semaphore/semaphore.nomad.hcl")
}

resource "nomad_job" "slskd" {
  jobspec = file("${path.module}/slskd/slskd.nomad.hcl")
}

resource "nomad_job" "sonarr" {
  jobspec = file("${path.module}/sonarr/sonarr.nomad.hcl")
}
