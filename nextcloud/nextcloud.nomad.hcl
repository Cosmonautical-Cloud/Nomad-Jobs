job "nextcloud" {
  datacenters = ["cosmonautical"]
  type        = "service"

  group "nextcloud" {
    count = 1

    ephemeral_disk {
      size    = 512
      migrate = true
      sticky  = true
    }

    network {
      port "http" { static = 8083 }
    }

    task "nextcloud" {
      driver = "raw_exec"

      artifact {
        source      = "https://download.nextcloud.com/server/releases/nextcloud-34.0.4.tar.bz2?archive=false"
        destination = "local/nextcloud-34.0.4.tar.bz2"
        mode        = "file"

        options {
          checksum = "sha256:00f226e6364f96e0918ab06157158f66601b8cedc25af777f5ee5a3056f42b83"
        }
      }

      artifact {
        source      = "https://github.com/caddyserver/caddy/releases/download/v2.11.4/caddy_2.11.4_mac_arm64.tar.gz"
        destination = "local/caddy/"

        options {
          checksum = "sha512:3190ae0df98b59ab4b6021556fa35adc3c526a4f3e138776b0eaec8a037cc26121cbbb1ad53453f565551b47d37d5ba4755e2c2c3652256737fe2ce9e53c8ec0"
        }
      }

      env {
        NEXTCLOUD_ADMIN_USER                = "admin"
        NEXTCLOUD_APP_DIR                   = "${NOMAD_ALLOC_DIR}/data/nextcloud"
        NEXTCLOUD_DATA_DIR                  = "/Volumes/Cosmonautical/nextcloud/data"
        OBJC_DISABLE_INITIALIZE_FORK_SAFETY = "YES"
        PATH                                = "/opt/homebrew/opt/php@8.4/bin:/opt/homebrew/opt/php@8.4/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
        PHP_INI_SCAN_DIR                    = "/opt/homebrew/etc/php/8.4/conf.d:${NOMAD_TASK_DIR}/php-conf"
        PGGSSENCMODE = "disable"
      }

      template {
        data        = <<EOT
memory_limit = 1G
opcache.memory_consumption = 256
opcache.max_accelerated_files = 30000
opcache.validate_timestamps = 0
opcache.interned_strings_buffer = 32
apc.shm_size = 128M
realpath_cache_size = 16M
realpath_cache_ttl = 600
EOT
        destination = "local/php-conf/nextcloud.ini"
      }

      template {
        data        = <<EOT
POSTGRES_PASSWORD={{ key "nextcloud/DB_PASSWORD" }}
REDIS_PASSWORD={{ key "redis/PASSWORD" }}
REDIS_HOST={{ range service "redis" }}{{ .Address }}{{ end }}
REDIS_PORT={{ range service "redis" }}{{ .Port }}{{ end }}
NEXTCLOUD_ADMIN_PASSWORD={{ key "nextcloud/ADMIN_PASSWORD" }}
EOT
        destination = "secrets/nextcloud.env"
        env         = true
      }

      template {
        data        = <<EOT
<?php
$CONFIG = [
  'dbhost' => '{{ range service "postgres" }}{{ .Address }}:{{ .Port }}{{ end }}',
    'datadirectory' => getenv('NEXTCLOUD_DATA_DIR'),
    'trusted_domains' => [
      'drive.cosmonautical.cloud',
    ],
    'trusted_proxies' => [
      '10.10.37.0/24',
    ],
    'apps_paths' => [
      [
        'path'     => getenv('NEXTCLOUD_APP_DIR') . '/apps',
        'url'      => '/apps',
        'writable' => false,
      ],
      [
        'path'     => getenv('NEXTCLOUD_APP_DIR') . '/custom_apps',
        'url'      => '/custom_apps',
        'writable' => true,
      ],
    ],
    'overwrite.cli.url'  => 'https://drive.cosmonautical.cloud',
    'overwriteprotocol'  => 'https',
    'files_external_allow_create_new_local' => true,
    'memcache.local'     => '\\OC\\Memcache\\APCu',
    'memcache.locking'   => '\\OC\\Memcache\\Redis',
    'memcache.distributed' => '\\OC\\Memcache\\Redis',
    'redis' => [
      'host'     => getenv('REDIS_HOST'),
      'port'     => (int) getenv('REDIS_PORT'),
        'dbindex'  => 1,
        'password' => getenv('REDIS_PASSWORD'),
        'timeout'  => 1.5,
    ],
    'mail_smtpmode'     => 'smtp',
    'mail_smtpsecure'   => 'tls',
    'mail_smtphost'     => '{{ key "smtp/SERVER" }}',
    'mail_smtpport'     => {{ key "smtp/PORT" }},
    'mail_smtpauth'     => true,
    'mail_smtpname'     => '{{ key "smtp/USERNAME" }}',
    'mail_smtppassword' => '{{ key "smtp/PASSWORD" }}',
    'mail_from_address' => 'valentina',
    'mail_domain'       => 'cosmonautical.cloud',
    'logfile' => '{{ env "NOMAD_ALLOC_DIR" }}/nextcloud-config/nextcloud.log',
    'log_rotate_size' => 20971520,
];
EOT
        destination = "secrets/nomad.config.php"
      }

      template {
        data        = <<EOT
[global]
daemonize = no
error_log = /dev/stderr
pid = {{ env "NOMAD_ALLOC_DIR" }}/php-fpm.pid

[www]
listen = {{ env "NOMAD_ALLOC_DIR" }}/php-fpm.sock
pm = static
pm.max_children = 12
pm.max_requests = 300
catch_workers_output = yes
clear_env = no
security.limit_extensions = .php
php_admin_value[memory_limit] = 1G
php_admin_value[upload_max_filesize] = 10G
php_admin_value[post_max_size] = 10G
php_admin_value[max_execution_time] = 3600
php_admin_value[max_input_time] = 3600

[health]
listen = {{ env "NOMAD_ALLOC_DIR" }}/php-fpm-health.sock
pm = static
pm.max_children = 2
catch_workers_output = yes
clear_env = no
security.limit_extensions = .php
php_admin_value[memory_limit] = 256M
php_admin_value[max_execution_time] = 30

[ui]
listen = {{ env "NOMAD_ALLOC_DIR" }}/php-fpm-ui.sock
pm = static
pm.max_children = 10
catch_workers_output = yes
clear_env = no
security.limit_extensions = .php
php_admin_value[memory_limit] = 1G
php_admin_value[max_execution_time] = 120
php_admin_value[max_input_time] = 120

[downloads]
listen = {{ env "NOMAD_ALLOC_DIR" }}/php-fpm-downloads.sock
listen.backlog = 256
pm = static
pm.max_children = 10
pm.max_requests = 300
catch_workers_output = yes
clear_env = no
security.limit_extensions = .php
php_admin_value[memory_limit] = 512M
php_admin_value[max_execution_time] = 300
php_admin_value[max_input_time] = 300
EOT
        destination = "local/php-fpm.conf"
      }

      template {
        data        = <<EOT
{
    admin off
    auto_https off
}

:8083 {
    root * {{ env "NEXTCLOUD_APP_DIR" }}
    encode zstd gzip
  header Strict-Transport-Security "max-age=15552000"

    route {
      redir /.well-known/carddav /remote.php/dav 301
      redir /.well-known/caldav /remote.php/dav 301

        @forbidden path /.htaccess /data/* /config/* /db_structure.xml /README
        respond @forbidden 404

        @legacyPhp {
          path_regexp legacy \.php(?:$|/)
          not path /index.php* /remote.php* /public.php* /cron.php* /core/ajax/update.php* /status.php* /ocs/v1.php* /ocs/v2.php* /updater/* /ocs-provider/*
        }
        rewrite @legacyPhp /index.php{uri}

        @statusCheck path /status.php
        php_fastcgi @statusCheck unix/{{ env "NOMAD_ALLOC_DIR" }}/php-fpm-health.sock {
            root {{ env "NEXTCLOUD_APP_DIR" }}
            env front_controller_active true
        }

        @davDownload {
          path /remote.php* /public.php*
          method GET HEAD
        }
        php_fastcgi @davDownload unix/{{ env "NOMAD_ALLOC_DIR" }}/php-fpm-downloads.sock {
            root {{ env "NEXTCLOUD_APP_DIR" }}
            env front_controller_active true
            dial_timeout 10s
            read_timeout 300s
        }

        @dav {
          path /remote.php* /public.php*
        }
        php_fastcgi @dav unix/{{ env "NOMAD_ALLOC_DIR" }}/php-fpm.sock {
            root {{ env "NEXTCLOUD_APP_DIR" }}
            env front_controller_active true
            dial_timeout 10s
            read_timeout 3600s
        }

        php_fastcgi unix/{{ env "NOMAD_ALLOC_DIR" }}/php-fpm-ui.sock {
            root {{ env "NEXTCLOUD_APP_DIR" }}
            env front_controller_active true
        }

        file_server
    }
}
EOT
        destination = "local/Caddyfile"
      }

      template {
        data        = <<EOT
#!/bin/sh
set -eu

app="$NEXTCLOUD_APP_DIR"
config_dir="$NOMAD_ALLOC_DIR/nextcloud-config"
apps_dir="/Volumes/Cosmonautical/nextcloud/persistent/custom_apps"
data_dir="$NEXTCLOUD_DATA_DIR"
fpm_socket="$NOMAD_ALLOC_DIR/php-fpm.sock"
fpm_health_socket="$NOMAD_ALLOC_DIR/php-fpm-health.sock"
fpm_ui_socket="$NOMAD_ALLOC_DIR/php-fpm-ui.sock"
fpm_downloads_socket="$NOMAD_ALLOC_DIR/php-fpm-downloads.sock"
fpm_pid_file="$NOMAD_ALLOC_DIR/php-fpm.pid"

if [ ! -f "$app/version.php" ]; then
  rm -rf "$app"
  mkdir -p "$NOMAD_ALLOC_DIR/data"
  /usr/bin/tar -xjf "$NOMAD_TASK_DIR/nextcloud-34.0.4.tar.bz2" -C "$NOMAD_ALLOC_DIR/data"
fi

mkdir -p "$config_dir" "$apps_dir" "$data_dir"

if [ ! -s "$config_dir/config.php" ] && [ -s /Volumes/Cosmonautical/nextcloud/persistent/config/config.php ]; then
  cp -a /Volumes/Cosmonautical/nextcloud/persistent/config/. "$config_dir/"
fi

rm -rf "$app/config" "$app/custom_apps"
ln -s "$config_dir" "$app/config"
ln -s "$apps_dir" "$app/custom_apps"

if [ ! -s "$config_dir/config.php" ]; then
  rm -f "$config_dir/config.php" "$config_dir/nomad.config.php"
  cd "$app"
  /opt/homebrew/opt/php@8.4/bin/php -d memory_limit=2G occ maintenance:install \
    --database pgsql \
    --database-host {{ range service "postgres" }}{{ .Address }}:{{ .Port }}{{ end }} \
    --database-name nextcloud \
    --database-user nextcloud \
    --database-pass "$POSTGRES_PASSWORD" \
    --admin-user "$NEXTCLOUD_ADMIN_USER" \
    --admin-pass "$NEXTCLOUD_ADMIN_PASSWORD" \
    --data-dir "$data_dir"
fi
cp "$NOMAD_SECRETS_DIR/nomad.config.php" "$config_dir/nomad.config.php"

cd "$app"

run_with_timeout() {
  secs="$1"; shift
  "$@" &
  cmd_pid=$!
  ( sleep "$secs"; kill -9 "$cmd_pid" 2>/dev/null ) &
  watchdog_pid=$!
  wait "$cmd_pid"
  status=$?
  kill "$watchdog_pid" 2>/dev/null || true
  wait "$watchdog_pid" 2>/dev/null || true
  return $status
}

php_bin="/opt/homebrew/opt/php@8.4/bin/php"

if ! run_with_timeout 90 "$php_bin" occ upgrade --no-interaction; then
  echo "occ upgrade timed out or failed" >&2
  exit 1
fi

run_with_timeout 20 "$php_bin" occ app:enable files_external >/dev/null 2>&1 || true
if ! run_with_timeout 20 "$php_bin" occ files_external:list --output=json | /usr/bin/python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
except ValueError:
    data = []
entries = data.values() if isinstance(data, dict) else data
sys.exit(0 if any(isinstance(e, dict) and e.get('mount_point') == '/ROMs' for e in entries) else 1)
"; then
  run_with_timeout 20 "$php_bin" occ files_external:create ROMs local null::null -c datadir=/Volumes/ROMs || true
fi

run_with_timeout 20 "$php_bin" occ app:enable previewgenerator >/dev/null 2>&1 || true

for sock in "$fpm_socket" "$fpm_health_socket" "$fpm_ui_socket" "$fpm_downloads_socket"; do
  if [ -S "$sock" ]; then
    for stale_pid in $(/usr/sbin/lsof -t "$sock" 2>/dev/null || true); do
      kill "$stale_pid" 2>/dev/null || true
    done
  fi
done
rm -f "$fpm_socket" "$fpm_health_socket" "$fpm_ui_socket" "$fpm_downloads_socket" "$fpm_pid_file"

/opt/homebrew/opt/php@8.4/sbin/php-fpm --nodaemonize --fpm-config "$NOMAD_TASK_DIR/php-fpm.conf" &
fpm_pid=$!
caddy_pid=""

sync_config_loop() {
  while true; do
    sleep 300
    cp -a "$config_dir/." /Volumes/Cosmonautical/nextcloud/persistent/config/ 2>/dev/null || true
  done
}
sync_config_loop &
sync_pid=$!

cleanup() {
    kill "$sync_pid" 2>/dev/null || true
    if [ -n "$caddy_pid" ]; then
      kill "$caddy_pid" 2>/dev/null || true
    fi
    kill "$fpm_pid" 2>/dev/null || true
    if [ -n "$caddy_pid" ]; then
      wait "$caddy_pid" 2>/dev/null || true
    fi
  wait "$fpm_pid" 2>/dev/null || true
  rm -f "$fpm_socket" "$fpm_health_socket" "$fpm_ui_socket" "$fpm_downloads_socket" "$fpm_pid_file"
}
trap cleanup EXIT INT TERM

sleep 1
if ! kill -0 "$fpm_pid" 2>/dev/null || [ ! -S "$fpm_socket" ] || [ ! -S "$fpm_health_socket" ] || [ ! -S "$fpm_ui_socket" ] || [ ! -S "$fpm_downloads_socket" ]; then
  wait "$fpm_pid"
  exit 1
fi

"$NOMAD_TASK_DIR/caddy/caddy" run --config "$NOMAD_TASK_DIR/Caddyfile" --adapter caddyfile &
caddy_pid=$!

while kill -0 "$fpm_pid" 2>/dev/null && kill -0 "$caddy_pid" 2>/dev/null; do
  sleep 1
done
exit 1
EOT
        destination = "local/start.sh"
        perms       = "755"
      }

      config {
        command = "${NOMAD_TASK_DIR}/start.sh"
      }

      service {
        name = "nextcloud"
        port = "http"

        tags = [
          "traefik.enable=true",
          "traefik.http.routers.nextcloud.rule=Host(`drive.cosmonautical.cloud`)",
          "traefik.http.routers.nextcloud.entrypoints=websecure",
          "traefik.http.routers.nextcloud.tls.certresolver=cf-dns"
        ]

        check {
          name     = "http"
          type     = "http"
          path     = "/status.php"
          interval = "30s"
          timeout  = "20s"

          header {
            Host = ["drive.cosmonautical.cloud"]
          }

          check_restart {
            limit           = 6
            grace           = "90s"
            ignore_warnings = false
          }
        }
      }

      resources {
        cpu    = 4
        memory = 8192
      }
    }
  }
}