resource "nomad_job" "nextcloud" {
  jobspec = file("${path.module}/nextcloud/nextcloud.nomad.hcl")
}

resource "nomad_job" "nextcloud-cron" {
  jobspec = file("${path.module}/nextcloud-cron/nextcloud-cron.nomad.hcl")
}

resource "nomad_job" "nextcloud-preview-generate" {
  jobspec = file("${path.module}/nextcloud-preview-generate/nextcloud-preview-generate.nomad.hcl")
}

resource "nomad_job" "nextcloud-s3-backup" {
  jobspec = file("${path.module}/nextcloud-s3-backup/nextcloud-s3-backup.nomad.hcl")
}

resource "nomad_job" "nextcloud-roms-scan" {
  jobspec = file("${path.module}/nextcloud-roms-scan/nextcloud-roms-scan.nomad.hcl")
}

resource "nomad_job" "postgres" {
  jobspec = file("${path.module}/postgres/postgres.nomad.hcl")
}

resource "nomad_job" "postgres-backup" {
  jobspec = file("${path.module}/postgres-backup/postgres-backup.nomad.hcl")
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
  jobspec = file("${path.module}/seaweedfs-filer/seaweedfs-filer.nomad.hcl")
}

resource "nomad_job" "seaweedfs-nfs-backup" {
  jobspec = file("${path.module}/seaweedfs-nfs-backup/seaweedfs-nfs-backup.nomad.hcl")
}
