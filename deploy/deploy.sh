#!/usr/bin/env bash
#
# deploy.sh - build and deploy the full application (frontend + backend repos)
# from ANY commit / branch / tag of each repo.
#
# Usage:
#   ./deploy.sh -F <frontend_repo_url> -B <backend_repo_url> \
#               [-f <frontend_ref>] [-b <backend_ref>] [-w <workspace>] [-p <port>] [-t]
#
#   -F / -B  git URLs (https, ssh or local path)
#   -f / -b  commit SHA, branch or tag to deploy (default: main)
#   -w       workspace for clones and deploy state (default: ~/deploy-workspace)
#   -p       host port for the app (default: 8080)
#   -t       skip running the backend unit tests
#
# Flow: clone/fetch -> checkout ref -> test -> docker build (tag = short SHA)
#       -> docker compose up -> health check -> record release
#       On a failed health check the previously deployed release is restored.
#
set -euo pipefail

FE_URL=""; BE_URL=""; FE_REF="main"; BE_REF="main"
WORKSPACE="$HOME/deploy-workspace"; PORT=8080; RUN_TESTS=true
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
PROJECT="demo-app"

usage() { sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
log()   { printf '\n[%s] %s\n' "$(date '+%F %T')" "$*"; }
die()   { echo "ERROR: $*" >&2; exit 1; }

while getopts ":F:B:f:b:w:p:th" o; do
  case "$o" in
    F) FE_URL="$OPTARG" ;;  B) BE_URL="$OPTARG" ;;
    f) FE_REF="$OPTARG" ;;  b) BE_REF="$OPTARG" ;;
    w) WORKSPACE="$OPTARG" ;; p) PORT="$OPTARG" ;;
    t) RUN_TESTS=false ;;   h) usage 0 ;;
    *) usage 2 ;;
  esac
done
[[ -n "$FE_URL" && -n "$BE_URL" ]] || usage 2
for cmd in git docker curl; do command -v "$cmd" >/dev/null || die "'$cmd' is required"; done

mkdir -p "$WORKSPACE"
STATE_FILE="$WORKSPACE/current_release"      # holds: FRONTEND_IMAGE / BACKEND_IMAGE of the live release
HISTORY_FILE="$WORKSPACE/release_history.log"

# Clone the repo if needed, fetch everything, check out the requested ref, print its short SHA.
checkout() {   # <url> <dir> <ref>
  local url="$1" dir="$2" ref="$3"
  if [[ -d "$dir/.git" ]]; then
    git -C "$dir" fetch --all --tags --prune --quiet >&2
  else
    git clone --quiet "$url" "$dir" >&2
  fi
  git -C "$dir" checkout --quiet --force "$ref" >&2 2>/dev/null \
    || git -C "$dir" checkout --quiet --force "origin/$ref" >&2 \
    || die "cannot check out '$ref' in $url"
  # Fast-forward when on a branch so "main" means the latest main
  if git -C "$dir" symbolic-ref -q HEAD >/dev/null; then
    git -C "$dir" pull --ff-only --quiet >&2 || true
  fi
  git -C "$dir" rev-parse --short=7 HEAD
}

health_check() {   # wait up to ~60s for backend (through nginx) to answer
  local url="http://localhost:$PORT/api/health"
  for i in $(seq 1 30); do
    if curl -fsS --max-time 3 "$url" >/dev/null 2>&1; then
      echo "healthy after $((i * 2))s"; return 0
    fi
    sleep 2
  done
  return 1
}

compose_up() {   # <frontend_image> <backend_image>
  FRONTEND_IMAGE="$1" BACKEND_IMAGE="$2" APP_PORT="$PORT" \
    docker compose -p "$PROJECT" -f "$COMPOSE_FILE" up -d --remove-orphans
}

# ---------------------------------------------------------------------------
log "1/6 Fetching source code"
FE_SHA="$(checkout "$FE_URL" "$WORKSPACE/frontend" "$FE_REF")"
BE_SHA="$(checkout "$BE_URL" "$WORKSPACE/backend"  "$BE_REF")"
echo "frontend @ $FE_SHA (ref: $FE_REF)"
echo "backend  @ $BE_SHA (ref: $BE_REF)"

FE_IMAGE="demo-frontend:$FE_SHA"
BE_IMAGE="demo-backend:$BE_SHA"

log "2/6 Building images"
docker build --pull -t "$BE_IMAGE" --build-arg GIT_COMMIT="$BE_SHA" "$WORKSPACE/backend"
docker build --pull -t "$FE_IMAGE" --build-arg GIT_COMMIT="$FE_SHA" "$WORKSPACE/frontend"

if $RUN_TESTS; then
  log "3/6 Running backend tests inside the built image"
  docker run --rm "$BE_IMAGE" npm test || die "tests failed - aborting, live release untouched"
else
  log "3/6 Tests skipped (-t)"
fi

log "4/6 Remembering the current release for rollback"
PREV_FE=""; PREV_BE=""
if [[ -f "$STATE_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$STATE_FILE"; PREV_FE="${FRONTEND_IMAGE:-}"; PREV_BE="${BACKEND_IMAGE:-}"
  echo "previous: $PREV_FE + $PREV_BE"
else
  echo "no previous release (first deployment)"
fi

log "5/6 Deploying $FE_IMAGE + $BE_IMAGE"
compose_up "$FE_IMAGE" "$BE_IMAGE"

log "6/6 Health check"
if health_check; then
  printf 'FRONTEND_IMAGE=%s\nBACKEND_IMAGE=%s\n' "$FE_IMAGE" "$BE_IMAGE" > "$STATE_FILE"
  echo "$(date '+%F %T') OK   frontend=$FE_SHA($FE_REF) backend=$BE_SHA($BE_REF)" >> "$HISTORY_FILE"
  log "SUCCESS: app live at http://localhost:$PORT"
else
  echo "$(date '+%F %T') FAIL frontend=$FE_SHA($FE_REF) backend=$BE_SHA($BE_REF)" >> "$HISTORY_FILE"
  log "FAILED health check"
  docker compose -p "$PROJECT" -f "$COMPOSE_FILE" logs --tail=30 || true
  if [[ -n "$PREV_FE" && -n "$PREV_BE" ]]; then
    log "Rolling back to $PREV_FE + $PREV_BE"
    compose_up "$PREV_FE" "$PREV_BE"
    health_check && echo "rollback successful" || echo "WARNING: rollback is also unhealthy!"
  else
    echo "No previous release to roll back to."
  fi
  exit 1
fi
