# SuiteCRM Docker Image

This repository includes a production-oriented Docker build for SuiteCRM 8.

## Build

```bash
docker build -t guerchele/suitecrm:8-latest .
```

## Runtime Configuration

Required variables unless `DATABASE_URL` is set:

- `DB_HOST`
- `DB_PORT` (default: `3306`)
- `DB_NAME`
- `DB_USER`
- `DB_PASSWORD`

Alternative:

- `DATABASE_URL`
  - Example: `mysql://suitecrm:password@db:3306/suitecrm?serverVersion=10.11.2-MariaDB&charset=utf8mb4`

Optional variables:

- `APP_ENV` (default: `prod`)
- `APP_DEBUG` (default: `0`)
- `APP_SECRET` (recommended for production)
- `SITE_URL` (default: `http://localhost`)
- `TZ` (default: `UTC`)
- `PHP_MEMORY_LIMIT` (default: `512M`)
- `UPLOAD_MAX_FILESIZE` (default: `50M`)
- `POST_MAX_SIZE` (default: `50M`)

## Optional Secret File Inputs

Sensitive variables can be provided with `*_FILE` variants. If both are set, `*_FILE` takes precedence.

Supported secret file variables:

- `DB_PASSWORD_FILE`
- `DB_USER_FILE`
- `DB_NAME_FILE`
- `DB_HOST_FILE`
- `DB_PORT_FILE`
- `DATABASE_URL_FILE`

Example:

```bash
docker run --rm -p 8080:80 \
  -e DB_HOST=db \
  -e DB_PORT=3306 \
  -e DB_NAME=suitecrm \
  -e DB_USER=suitecrm \
  -e DB_PASSWORD_FILE=/run/secrets/db_password \
  -v $(pwd)/db_password.txt:/run/secrets/db_password:ro \
  guerchele/suitecrm:8-latest
```

## Local Validation Stack

```bash
docker compose up -d --build
```

Open `http://localhost:8080` and complete the SuiteCRM installer.

## Push To Docker Hub

```bash
docker push guerchele/suitecrm:8-latest
```
