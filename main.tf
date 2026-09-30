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
