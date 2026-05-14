#!/usr/bin/env zsh
# Updates the guerchele/SuiteCRM-Core Docker Hub repository overview.
# Called automatically by build-push.zsh, or run standalone:
#   ./docker/push-hub-overview.zsh [version]
#
# Reads Docker Hub credentials from the local Docker credential store
# (populated by 'docker login').

set -euo pipefail

DOCKERHUB_NAMESPACE="guerchele"
DOCKERHUB_REPO="SuiteCRM-Core"
VERSION="${1:-}"

# ── Build the overview markdown ────────────────────────────────────────────────
OVERVIEW=$(cat <<'MARKDOWN'
# guerchele/SuiteCRM-Core

Unofficial multi-arch Docker image for **SuiteCRM Core** (the Symfony-based v8 rewrite), built from the [salesagility/SuiteCRM-Core](https://github.com/salesagility/SuiteCRM-Core) source.

Supported platforms: `linux/amd64`, `linux/arm64`

---

## Tags

| Tag | Description |
|-----|-------------|
| `8-latest` | Latest stable SuiteCRM 8 release |
| `v8.x.y` | Pinned release (e.g. `v8.10.0`) |

---

## Quick start

```yaml
# docker-compose.yml
services:
  db:
    image: mariadb:10.11
    environment:
      MARIADB_ROOT_PASSWORD: rootpass
      MARIADB_DATABASE: suitecrm
      MARIADB_USER: suitecrm
      MARIADB_PASSWORD: suitecrm
    volumes:
      - db_data:/var/lib/mysql

  suitecrm:
    image: guerchele/suitecrm:8-latest
    ports:
      - "8080:80"
    environment:
      DATABASE_HOST: db
      DATABASE_NAME: suitecrm
      DATABASE_USER: suitecrm
      DATABASE_PASSWORD: suitecrm
    depends_on:
      - db

volumes:
  db_data:
```

```bash
docker compose up -d
# Open http://localhost:8080 and follow the web installer.
```

---

## Environment variables

### Required (or use `DATABASE_URL`)

| Variable | Description |
|----------|-------------|
| `DATABASE_HOST` | MySQL/MariaDB hostname |
| `DATABASE_NAME` | Database name |
| `DATABASE_USER` | Database user |
| `DATABASE_PASSWORD` | Database password |

### Optional

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | — | Full DSN — overrides the four vars above |
| `DATABASE_PORT` | `3306` | Database port |
| `SITE_URL` | `http://localhost` | Public URL of the instance |
| `PHP_MEMORY_LIMIT` | `256M` | PHP memory limit |
| `PHP_MAX_EXECUTION_TIME` | `300` | PHP max execution time (seconds) |
| `PHP_UPLOAD_MAX_FILESIZE` | `20M` | PHP upload size limit |
| `PHP_POST_MAX_SIZE` | `20M` | PHP POST size limit |

### Secrets file support

Every variable above accepts a `_FILE` companion that points to a file containing the value — useful with Docker secrets:

```yaml
environment:
  DATABASE_PASSWORD_FILE: /run/secrets/db_password
secrets:
  - db_password
```

---

## Persistent data

Mount these paths to preserve data across container restarts:

| Path | Contents |
|------|----------|
| `/var/www/html/public/legacy/upload` | Uploaded files |
| `/var/www/html/public/legacy/cache` | Application cache |
| `/var/www/html/logs` | Application logs |

---

## Source & build

Image built from [github.com/guerchele/SuiteCRM-Core](https://github.com/guerchele/SuiteCRM-Core).  
Base image: `php:8.2-apache` · Extensions: `gd`, `intl`, `mbstring`, `mysqli`, `pdo_mysql`, `soap`, `zip`, `ldap`, `opcache`
MARKDOWN
)

# Append current version if provided
if [[ -n "$VERSION" ]]; then
  OVERVIEW="${OVERVIEW}

---

*Last published version: ${VERSION}*"
fi

# ── Obtain a Docker Hub JWT ────────────────────────────────────────────────────
_hub_token() {
  python3 - <<PYEOF
import json, base64, urllib.request, sys

try:
    with open("${HOME}/.docker/config.json") as f:
        cfg = json.load(f)
except Exception as e:
    sys.exit(f"Cannot read ~/.docker/config.json: {e}")

auth_b64 = (cfg.get("auths", {})
               .get("https://index.docker.io/v1/", {})
               .get("auth", ""))

if not auth_b64:
    # Try the credential helper
    import subprocess
    try:
        out = subprocess.check_output(
            ["docker-credential-osxkeychain", "get"],
            input=b"https://index.docker.io/v1/\n"
        )
        creds = json.loads(out)
        user, pw = creds["Username"], creds["Secret"]
    except Exception as e:
        sys.exit(f"No Docker Hub credentials found: {e}")
else:
    user, pw = base64.b64decode(auth_b64).decode().split(":", 1)

req = urllib.request.Request(
    "https://hub.docker.com/v2/users/login",
    data=json.dumps({"username": user, "password": pw}).encode(),
    headers={"Content-Type": "application/json"},
    method="POST",
)
try:
    res = json.loads(urllib.request.urlopen(req).read())
    print(res["token"])
except Exception as e:
    sys.exit(f"Docker Hub login failed: {e}")
PYEOF
}

TOKEN=$(_hub_token)

# ── PATCH the repository overview ─────────────────────────────────────────────
python3 - "$TOKEN" "$OVERVIEW" <<'PYEOF'
import sys, json, urllib.request

token   = sys.argv[1]
content = sys.argv[2]

url  = "https://hub.docker.com/v2/repositories/guerchele/suitecrm/"
data = json.dumps({"full_description": content}).encode()
req  = urllib.request.Request(url, data=data, method="PATCH",
        headers={"Content-Type": "application/json",
                 "Authorization": f"Bearer {token}"})
try:
    res = urllib.request.urlopen(req)
    print("  Overview updated successfully.")
except urllib.error.HTTPError as e:
    print(f"  HTTPError {e.code}: {e.read().decode()}", file=sys.stderr)
    sys.exit(1)
PYEOF
