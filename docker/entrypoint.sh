#!/usr/bin/env sh
set -eu

file_env() {
  var="$1"
  file_var="${var}_FILE"
  default_value="${2:-}"

  eval var_value="\${$var:-}"
  eval file_value="\${$file_var:-}"

  if [ -n "$file_value" ]; then
    if [ ! -r "$file_value" ]; then
      echo "[entrypoint] ERROR: cannot read file from ${file_var}=${file_value}" >&2
      exit 1
    fi
    var_value="$(cat "$file_value")"
  fi

  if [ -z "$var_value" ]; then
    var_value="$default_value"
  fi

  export "$var=$var_value"
  unset "$file_var"
}

require_env() {
  name="$1"
  eval value="\${$name:-}"
  if [ -z "$value" ]; then
    echo "[entrypoint] ERROR: required environment variable '$name' is missing" >&2
    exit 1
  fi
}

file_env DATABASE_HOST
file_env DATABASE_PORT "3306"
file_env DATABASE_NAME
file_env DATABASE_USER
file_env DATABASE_PASSWORD
file_env DATABASE_URL

file_env APP_ENV "prod"
file_env APP_DEBUG "0"
file_env SITE_URL "http://localhost"
file_env TZ "UTC"
file_env PHP_MEMORY_LIMIT "512M"
file_env UPLOAD_MAX_FILESIZE "50M"
file_env POST_MAX_SIZE "50M"

export APP_ENV APP_DEBUG SITE_URL TZ

if [ -z "${DATABASE_URL:-}" ]; then
  require_env DATABASE_HOST
  require_env DATABASE_PORT
  require_env DATABASE_NAME
  require_env DATABASE_USER
  require_env DATABASE_PASSWORD
  DATABASE_URL="mysql://${DATABASE_USER}:${DATABASE_PASSWORD}@${DATABASE_HOST}:${DATABASE_PORT}/${DATABASE_NAME}?serverVersion=10.11.2-MariaDB&charset=utf8mb4"
  export DATABASE_URL
fi

if [ -z "${APP_SECRET:-}" ]; then
  echo "[entrypoint] WARNING: APP_SECRET is not set. Set APP_SECRET in production." >&2
fi

cat >/usr/local/etc/php/conf.d/zz-suitecrm-runtime.ini <<EOF
memory_limit=${PHP_MEMORY_LIMIT}
upload_max_filesize=${UPLOAD_MAX_FILESIZE}
post_max_size=${POST_MAX_SIZE}
date.timezone=${TZ}
EOF

for dir in \
  /var/www/html/logs \
  /var/www/html/tmp \
  /var/www/html/cache \
  /var/www/html/public/legacy \
  /var/www/html/public/legacy/cache \
  /var/www/html/public/legacy/custom \
  /var/www/html/public/legacy/modules \
  /var/www/html/public/legacy/themes \
  /var/www/html/public/legacy/upload
do
  mkdir -p "$dir"
  chown -R www-data:www-data "$dir"
  chmod -R ug+rwX "$dir"
done

# Run Symfony cache clear to rebuild legacy assets (like CSS)
if [ -f "bin/console" ]; then
  # We are running as root prior to apache starting, so we chown afterwards
  php bin/console cache:clear --env="${APP_ENV:-prod}" || true
  php bin/console suitecrm:app:setup-legacy-routes || true
  # Make sure the cache we just generated is completely owned by www-data
  chown -R www-data:www-data /var/www/html/cache /var/www/html/public/legacy/cache
fi

exec "$@"
