job "openldap" {
  datacenters = ["cosmonautical"]
  type        = "service"

  group "openldap" {
    count = 1

    ephemeral_disk {
      size    = 200
      migrate = true
      sticky  = true
    }

    network {
      port "ldap" { static = 3890 }
    }

    task "seed-data" {
      driver = "raw_exec"

      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      template {
        data        = <<EOT
include /opt/homebrew/etc/openldap/schema/core.schema
include /opt/homebrew/etc/openldap/schema/cosine.schema
include /opt/homebrew/etc/openldap/schema/inetorgperson.schema
include /opt/homebrew/etc/openldap/schema/nis.schema

database  mdb
maxsize   1073741824
suffix    "dc=cosmonautical,dc=cloud"
rootdn    "cn=admin,dc=cosmonautical,dc=cloud"
directory {{ env "NOMAD_ALLOC_DIR" }}/openldap-data
EOT
        destination = "local/restore-slapd.conf"
      }

      config {
        command = "/bin/sh"
        args = [
          "-c",
          <<-EOT
          set -eu
          data_dir="$NOMAD_ALLOC_DIR/openldap-data"
          mkdir -p "$data_dir"
          chmod 700 "$data_dir"
          backup=/Volumes/Cosmonautical/openldap/persistent/openldap-backup.ldif
          if [ ! -s "$data_dir/data.mdb" ] && [ -s "$backup" ]; then
            /opt/homebrew/opt/openldap/sbin/slapadd -f "$NOMAD_TASK_DIR/restore-slapd.conf" -l "$backup"
          fi
          EOT
        ]
      }

      resources {
        cpu    = 1
        memory = 16
      }
    }

    task "openldap" {
      driver = "raw_exec"

      config {
        command = "${NOMAD_TASK_DIR}/start.sh"
      }

      template {
        data        = <<EOT
#!/bin/sh
set -eu

slapd_bin="/opt/homebrew/opt/openldap/libexec/slapd"
slapcat_bin="/opt/homebrew/opt/openldap/sbin/slapcat"
conf="$NOMAD_TASK_DIR/slapd.conf"
backup_dir="/Volumes/Cosmonautical/openldap/persistent"

"$slapd_bin" -f "$conf" -h "ldap://0.0.0.0:3890/" -d 0 &
slapd_pid=$!

backup_loop() {
  local_backup="$NOMAD_ALLOC_DIR/openldap-backup.ldif"
  while true; do
    sleep 900
    "$slapcat_bin" -f "$conf" -l "$local_backup.tmp" 2>/dev/null || continue
    mv "$local_backup.tmp" "$local_backup" || continue
    mkdir -p "$backup_dir" 2>/dev/null || continue
    cp "$local_backup" "$backup_dir/openldap-backup.ldif" 2>/dev/null || continue
  done
}
backup_loop &
backup_pid=$!

cleanup() {
  kill "$backup_pid" 2>/dev/null || true
  kill "$slapd_pid" 2>/dev/null || true
  wait "$slapd_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

wait "$slapd_pid"
EOT
        destination = "local/start.sh"
        perms       = "755"
      }

      template {
        data        = <<EOT
include /opt/homebrew/etc/openldap/schema/core.schema
include /opt/homebrew/etc/openldap/schema/cosine.schema
include /opt/homebrew/etc/openldap/schema/inetorgperson.schema
include /opt/homebrew/etc/openldap/schema/nis.schema

pidfile  {{ env "NOMAD_TASK_DIR" }}/slapd.pid
argsfile {{ env "NOMAD_TASK_DIR" }}/slapd.args

database  mdb
maxsize   1073741824
suffix    "dc=cosmonautical,dc=cloud"
rootdn    "cn=admin,dc=cosmonautical,dc=cloud"
rootpw    "{{ key "openldap/ROOT_PASSWORD" }}"
directory {{ env "NOMAD_ALLOC_DIR" }}/openldap-data
index     objectClass eq

overlay memberof
memberof-group-oc  groupOfNames
memberof-member-ad member
memberof-memberof-ad memberOf

access to dn.subtree="ou=users,dc=cosmonautical,dc=cloud"
  by dn.exact="cn=keycloak,ou=service-accounts,dc=cosmonautical,dc=cloud" write
  by dn.exact="cn=nextcloud,ou=service-accounts,dc=cosmonautical,dc=cloud" read
  by * read
access to dn.subtree="ou=groups,dc=cosmonautical,dc=cloud"
  by dn.exact="cn=keycloak,ou=service-accounts,dc=cosmonautical,dc=cloud" write
  by dn.exact="cn=nextcloud,ou=service-accounts,dc=cosmonautical,dc=cloud" read
  by * read
access to *
  by * read
EOT
        destination = "local/slapd.conf"
      }

      service {
        name = "openldap"
        port = "ldap"

        check {
          name     = "tcp"
          type     = "tcp"
          port     = "ldap"
          interval = "10s"
          timeout  = "2s"
        }
      }

      resources {
        cpu    = 2
        memory = 256
      }
    }
  }
}
