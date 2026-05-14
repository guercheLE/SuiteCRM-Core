#!/usr/bin/env zsh
# Usage: ./docker/build-push.zsh <version>
# Example: ./docker/build-push.zsh v8.10.0
#
# Builds a multi-arch (linux/amd64 + linux/arm64) SuiteCRM image and pushes it
# to Docker Hub under guerchele/suitecrm:<version> and guerchele/suitecrm:8-latest.

set -euo pipefail

DOCKERHUB_REPO="guerchele/suitecrm"
BUILDER="multiarch"

# ── Version argument ────────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
  print -u2 "Usage: $0 <version>  (e.g. v8.10.0)"
  exit 1
fi

VERSION="$1"
# Derive the major-version floating tag from the version string (v8.x.y -> 8)
MAJOR=$(print "$VERSION" | grep -oE '[0-9]+' | head -1)
FLOATING_TAG="${DOCKERHUB_REPO}:${MAJOR}-latest"
VERSION_TAG="${DOCKERHUB_REPO}:${VERSION}"

print "▶ Building and pushing:"
print "    ${VERSION_TAG}"
print "    ${FLOATING_TAG}"
print "  Platforms: linux/amd64, linux/arm64"
print ""

# ── Build Angular frontend ─────────────────────────────────────────────────────
# Yarn 4 is distributed via Corepack. Install corepack if it isn't available,
# then put Node's bin dir first in PATH so its shim wins over any Homebrew yarn 1.
if ! command -v corepack &>/dev/null; then
  print "▶ Installing Corepack (overwriting Homebrew yarn shim) …"
  npm install -g corepack --force
fi

print "▶ Enabling Corepack …"
corepack enable

NODE_BIN=$(dirname "$(command -v node)")
export PATH="${NODE_BIN}:${PATH}"

# Install PHP and Composer locally if missing
if ! command -v php &>/dev/null; then
  print "▶ Installing PHP via Homebrew …"
  brew install php
fi

if ! command -v composer &>/dev/null; then
  print "▶ Installing Composer via Homebrew …"
  brew install composer
fi

print "▶ Installing PHP dependencies (Composer) …"
COMPOSER_MEMORY_LIMIT=-1 composer install --ignore-platform-reqs --no-interaction

print "▶ Copying Legacy Assets …"
php -d memory_limit=-1 bin/console scrm:copy-legacy-assets

print "▶ Cleaning Yarn Cache …"
yarn cache clean

print "▶ Installing JS dependencies …"
yarn install --frozen-lockfile

print "▶ Setting local file permissions …"
mkdir -p logs cache tmp public/legacy/cache public/legacy/custom public/legacy/modules public/legacy/themes public/legacy/data public/legacy/upload logs/prod
chmod -R 775 logs cache tmp public/legacy/cache public/legacy/custom public/legacy/modules public/legacy/themes public/legacy/data public/legacy/upload logs/prod || true

print "▶ Generating angular.json …"
yarn merge-angular-json

print "▶ Building Angular frontend …"
yarn build

print ""

# ── Ensure the buildx builder exists ───────────────────────────────────────────
if ! docker buildx inspect "$BUILDER" &>/dev/null; then
  print "▶ Creating buildx builder '${BUILDER}' …"
  docker buildx create --name "$BUILDER" --driver docker-container --use
else
  docker buildx use "$BUILDER"
fi

# ── Build & push ───────────────────────────────────────────────────────────────
docker buildx build \
  --builder "$BUILDER" \
  --platform linux/amd64,linux/arm64 \
  -t "$VERSION_TAG" \
  -t "$FLOATING_TAG" \
  --push \
  .

# ── Verify manifests ───────────────────────────────────────────────────────────
print ""
print "▶ Verifying manifests …"
docker buildx imagetools inspect "$FLOATING_TAG"

print ""
print "✓ Done — ${VERSION_TAG} and ${FLOATING_TAG} are live on Docker Hub."

# ── Update Docker Hub repository overview ─────────────────────────────────────
print ""
print "▶ Updating Docker Hub repository overview …"
"${0:A:h}/push-hub-overview.zsh" "$VERSION" || print "  Warning: overview update failed (non-fatal)"

# ── Remove any leftover tmp tags from Docker Hub ───────────────────────────────
# These may exist if a previous interrupted build left them behind.
for tmp_tag in amd64-tmp arm64-tmp; do
  full="${DOCKERHUB_REPO}:${tmp_tag}"
  if docker buildx imagetools inspect "$full" &>/dev/null; then
    print "▶ Removing leftover tag ${full} …"
    docker buildx imagetools create --tag "$full" --dry-run &>/dev/null || true
    # Hub deletion requires the registry API; use curl with the stored credentials.
    local _token
    _token=$(cat ~/.docker/config.json 2>/dev/null \
      | python3 -c "
import sys, json, base64
cfg = json.load(sys.stdin)
repo = '${DOCKERHUB_REPO}'.split('/')[0]
auth = cfg.get('auths', {}).get('https://index.docker.io/v1/', {}).get('auth', '')
if auth:
    user, pw = base64.b64decode(auth).decode().split(':', 1)
    import urllib.request, urllib.parse
    req = urllib.request.Request(
        'https://hub.docker.com/v2/users/login',
        data=json.dumps({'username': user, 'password': pw}).encode(),
        headers={'Content-Type': 'application/json'},
        method='POST'
    )
    res = json.loads(urllib.request.urlopen(req).read())
    print(res.get('token', ''))
" 2>/dev/null)
    if [[ -n "$_token" ]]; then
      local _ns _repo
      _ns="${DOCKERHUB_REPO%/*}"
      _repo="${DOCKERHUB_REPO#*/}"
      curl -sf -X DELETE \
        -H "Authorization: Bearer ${_token}" \
        "https://hub.docker.com/v2/repositories/${_ns}/${_repo}/tags/${tmp_tag}/" \
        && print "  Deleted ${full}" \
        || print "  Could not delete ${full} (may already be gone)"
    else
      print "  Skipping deletion of ${full} — could not obtain Hub token (log in with 'docker login' first)"
    fi
  fi
done
