#!/usr/bin/env bash
#
# Proves the destination's central claim: a clean Ubuntu machine plus a git clone
# plus one command yields a working stack.
#
# Asserts a full round trip, not liveness - it synthesises its own media fixture,
# makes Jellyfin index it, and streams bytes back. Containers reaching "running"
# and UIs returning 200 were both already true while the library was unreadable,
# so neither is worth asserting on its own.
#
# Runs identically on a GitHub Actions ubuntu-24.04 runner and on a developer
# machine: it copies the compose file into a scratch workspace under its own
# project name, so it never touches a live stack's config or library.
#
# Docker and the compose plugin are PREREQUISITES. This script asserts them and
# fails loudly; it does not install them.
#
# Usage: scripts/verify-portability.sh
# Exit:  0 all assertions passed, non-zero on the first failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="media-server-verify"
WORKDIR="$(mktemp -d -t media-server-verify-XXXXXX)"
MEDIA_ROOT="${WORKDIR}/media"

# Deliberately off the defaults: the harness must be able to run while a live
# stack is up on this host, otherwise it can only ever be a CI-only test.
JELLYFIN_PORT=18096
RADARR_PORT=17878
SONARR_PORT=18989

ADMIN_USER="verify"
ADMIN_PASS="verify-$$-portability"

FIXTURE_TITLE="Portability Fixture (2000)"

pass() { printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1" >&2; exit 1; }
step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

cleanup() {
  local rc=$?
  step "Teardown"
  if [ "$rc" -ne 0 ]; then
    echo "--- container logs (last 40 lines each) ---"
    docker compose -p "$PROJECT" -f "${WORKDIR}/compose.yaml" logs --tail=40 2>&1 || true
  fi
  docker compose -p "$PROJECT" -f "${WORKDIR}/compose.yaml" down -v >/dev/null 2>&1 || true
  # Config is written by containers as PUID/PGID; if that is not us, we cannot
  # remove it directly. Borrow a container to do it rather than demanding sudo.
  if [ -d "${WORKDIR}/config" ] && ! rm -rf "${WORKDIR}/config" 2>/dev/null; then
    docker run --rm -v "${WORKDIR}:/w" alpine:3 sh -c 'rm -rf /w/config' >/dev/null 2>&1 || true
  fi
  rm -rf "$WORKDIR" 2>/dev/null || true
  [ "$rc" -eq 0 ] && printf '\n\033[32mPORTABILITY VERIFIED\033[0m\n' || printf '\n\033[31mPORTABILITY CHECK FAILED\033[0m\n'
  exit $rc
}
trap cleanup EXIT

# --- 1. prerequisites -------------------------------------------------------
step "Prerequisites (asserted, never installed)"

command -v docker >/dev/null 2>&1 \
  || fail "docker not found. It is a prerequisite: https://docs.docker.com/engine/install/ubuntu/"
pass "docker present: $(docker --version)"

docker compose version >/dev/null 2>&1 \
  || fail "'docker compose' not available. The Compose v2 plugin is a prerequisite."
pass "compose plugin present: $(docker compose version --short)"

docker info >/dev/null 2>&1 \
  || fail "cannot talk to the Docker daemon. Is it running, and is this user in the 'docker' group?"
pass "docker daemon reachable"

# --- 2. scratch workspace ---------------------------------------------------
step "Scratch workspace"

cp "${REPO_ROOT}/compose.yaml" "${WORKDIR}/compose.yaml"
mkdir -p "${MEDIA_ROOT}/movies" "${MEDIA_ROOT}/tv"

# Deliberately NOT copying the repo's .env. A clean host has none, so the test
# builds one the way a new user would: from .env.example, with MEDIA_ROOT
# repointed. If MEDIA_ROOT is not a real seam, this is where it breaks.
[ -f "${REPO_ROOT}/.env.example" ] || fail ".env.example missing from the repo"
sed -e "s#^MEDIA_ROOT=.*#MEDIA_ROOT=${MEDIA_ROOT}#" \
    -e "s#^PUID=.*#PUID=$(id -u)#" \
    -e "s#^PGID=.*#PGID=$(id -g)#" \
    "${REPO_ROOT}/.env.example" > "${WORKDIR}/.env"
cat >> "${WORKDIR}/.env" <<EOF
JELLYFIN_PORT=${JELLYFIN_PORT}
RADARR_PORT=${RADARR_PORT}
SONARR_PORT=${SONARR_PORT}
EOF
pass "built .env from .env.example with MEDIA_ROOT=${MEDIA_ROOT}"

dc() { docker compose -p "$PROJECT" -f "${WORKDIR}/compose.yaml" --env-file "${WORKDIR}/.env" "$@"; }

dc config --quiet || fail "compose.yaml does not parse, or a variable is unresolved"
pass "compose.yaml parses with every variable resolved"

# --- 3. the one command -----------------------------------------------------
step "docker compose up -d"

dc up -d --quiet-pull >/dev/null 2>&1 || fail "'docker compose up -d' failed"
pass "stack started"

# Readiness, not liveness. Jellyfin serves HTTP 200 on "/" (static web UI) while
# the server itself is still starting and every API call answers
# 503 "Jellyfin Server is loading". Polling "/" therefore passes too early and the
# next step fails for a reason that looks unrelated. Probe an endpoint that only
# answers once the application is genuinely up, and match on its body.
wait_ready() {
  local name="$1" port="$2" path="$3" needle="$4" i body
  for i in $(seq 1 90); do
    body=$(curl -s --max-time 5 "http://127.0.0.1:${port}${path}" || true)
    case "$body" in
      *"$needle"*) pass "${name} ready after ~$((i*2))s"; return 0 ;;
    esac
    sleep 2
  done
  fail "${name} never became ready on port ${port}${path} (last body: ${body:0:120})"
}

wait_ready jellyfin "$JELLYFIN_PORT" /System/Info/Public '"Version"'
wait_ready radarr   "$RADARR_PORT"   /ping                '"OK"'
wait_ready sonarr   "$SONARR_PORT"   /ping                '"OK"'

# --- 4. shared library path -------------------------------------------------
step "Library path identity across services"

# Hardlinking and atomic moves on *arr import depend on all three services
# seeing the library at the SAME container path. Assert it rather than trust it.
for svc in jellyfin radarr sonarr; do
  out=$(dc exec -T "$svc" ls /data 2>/dev/null | tr -d '\r' | sort | tr '\n' ' ' | xargs)
  [ "$out" = "movies tv" ] || fail "${svc} sees '/data' as '${out}', expected 'movies tv'"
done
pass "all three services see the library at /data with movies+tv"

# --- 5. synthesise the fixture ----------------------------------------------
step "Media fixture"

# Generated, never downloaded: deterministic, tiny, no licensing question, and
# identical on CI where no library exists.
dc exec -T jellyfin mkdir -p "/data/movies/${FIXTURE_TITLE}" \
  || fail "could not create the fixture directory under /data (bind mount permissions?)"

dc exec -T jellyfin /usr/lib/jellyfin-ffmpeg/ffmpeg \
  -f lavfi -i testsrc=duration=5:size=640x480:rate=24 \
  -f lavfi -i sine=frequency=440:duration=5 \
  -c:v libx264 -preset ultrafast -pix_fmt yuv420p -c:a aac -shortest \
  -y "/data/movies/${FIXTURE_TITLE}/${FIXTURE_TITLE}.mp4" >/dev/null 2>&1 \
  || fail "ffmpeg could not write the fixture into the library"

host_file="${MEDIA_ROOT}/movies/${FIXTURE_TITLE}/${FIXTURE_TITLE}.mp4"
[ -s "$host_file" ] || fail "fixture is not visible on the host at ${host_file} - the bind mount is not working"
pass "fixture written and visible on the host ($(du -h "$host_file" | cut -f1))"

# --- 6. Jellyfin round trip -------------------------------------------------
step "Jellyfin round trip"

AUTH_HDR='MediaBrowser Client="portability-check", Device="ci", DeviceId="portability-check", Version="1.0.0"'
JF="http://127.0.0.1:${JELLYFIN_PORT}"

# The /Startup/* endpoints sit behind Jellyfin's FirstTimeSetupOrElevated policy.
# Sending X-Emby-Authorization makes Jellyfin treat the call as authenticated, the
# policy then fails, and it answers 404 rather than 403. Send no auth header here.
# Never swallow the status. A bare "it failed" here costs more to diagnose than
# the whole check is worth, so every wizard call reports its real code and body.
post_json() {
  local desc="$1" url="$2" body="${3:-}" out code
  if [ -n "$body" ]; then
    out=$(curl -s -w '\n%{http_code}' -X POST "$url" -H 'Content-Type: application/json' -d "$body" || true)
  else
    out=$(curl -s -w '\n%{http_code}' -X POST "$url" || true)
  fi
  code="${out##*$'\n'}"
  case "$code" in
    2*) return 0 ;;
    *)  fail "${desc}: HTTP ${code:-none} - $(printf '%s' "${out%$'\n'*}" | head -c 200)" ;;
  esac
}

post_json "startup configuration" "${JF}/Startup/Configuration" \
  '{"UICulture":"en-US","MetadataCountryCode":"US","PreferredMetadataLanguage":"en"}'

# GET first, and not for symmetry: it materialises the default startup user that
# the POST then renames. Without it the POST has nothing to update and Jellyfin
# answers 404.
curl -sf "${JF}/Startup/User" >/dev/null || fail "could not read the startup user"

post_json "create admin user" "${JF}/Startup/User" \
  "{\"Name\":\"${ADMIN_USER}\",\"Password\":\"${ADMIN_PASS}\"}"

post_json "complete startup wizard" "${JF}/Startup/Complete"
pass "startup wizard completed"

TOKEN=$(curl -sf -X POST "${JF}/Users/AuthenticateByName" \
  -H 'Content-Type: application/json' \
  -H "X-Emby-Authorization: ${AUTH_HDR}" \
  -d "{\"Username\":\"${ADMIN_USER}\",\"Pw\":\"${ADMIN_PASS}\"}" \
  | grep -o '"AccessToken":"[^"]*"' | cut -d'"' -f4)
[ -n "${TOKEN:-}" ] || fail "authentication returned no access token"
pass "authenticated as ${ADMIN_USER}"

jf() { curl -s -H "X-Emby-Token: ${TOKEN}" -H "X-Emby-Authorization: ${AUTH_HDR}" "$@"; }

jf -f -X POST "${JF}/Library/VirtualFolders?name=Movies&collectionType=movies&paths=%2Fdata%2Fmovies&refreshLibrary=true" \
  -H 'Content-Type: application/json' -d '{}' >/dev/null \
  || fail "could not add the Movies library pointing at /data/movies"
pass "Movies library added at /data/movies"

ITEM_ID=""
for i in $(seq 1 60); do
  ITEM_ID=$(jf "${JF}/Items?Recursive=true&IncludeItemTypes=Movie&Limit=10" \
    | grep -o '"Id":"[^"]*"' | head -1 | cut -d'"' -f4 || true)
  [ -n "$ITEM_ID" ] && break
  jf -X POST "${JF}/Library/Refresh" >/dev/null 2>&1 || true
  sleep 2
done
[ -n "$ITEM_ID" ] || fail "Jellyfin never indexed the fixture - it can see the mount but not read the library"
pass "fixture indexed by Jellyfin (item ${ITEM_ID}) after ~$((i*2))s"

# The assertion that actually matters: bytes come back out.
BYTES=$(jf -o /dev/null -w '%{size_download}' \
  -H 'Range: bytes=0-65535' \
  "${JF}/Videos/${ITEM_ID}/stream?static=true" || echo 0)
[ "${BYTES:-0}" -gt 1024 ] \
  || fail "streaming returned ${BYTES} bytes - Jellyfin indexed the file but cannot serve it"
pass "streamed ${BYTES} bytes back from the library"
