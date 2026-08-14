#!/usr/bin/env bash
#
# Proves the destination's central claim: a clean Ubuntu machine plus a git clone
# plus "docker compose up -d" plus "scripts/seed.sh" yields a working stack that
# already knows this repo's conventions.
#
# Asserts a full round trip, not liveness - it synthesises its own media fixture,
# makes Jellyfin index it, and streams bytes back. Containers reaching "running"
# and UIs returning 200 were both already true while the library was unreadable,
# so neither is worth asserting on its own.
#
# It BOOTSTRAPS THROUGH scripts/seed.sh rather than keeping its own inline copy.
# Otherwise the bootstrap that ships to users is the one CI never exercises, and
# the naming conventions get asserted in two places that rot apart. A consequence
# worth knowing: running the seed a second time and requiring a no-op is what
# asserts the running stack still matches seed/conventions.json, because the
# seeder IS the drift checker. There is no separate comparison to maintain.
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

# Injected into .env below, then consumed by the seed. Nothing here is ever read
# back off disk - the same "secrets are injected, never discovered" rule the seed
# is built on.
ADMIN_USER="verify"
ADMIN_PASS="verify-$$-portability"
RADARR_API_KEY="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"
SONARR_API_KEY="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"

# Convention-shaped on purpose (WF-003): "Title (Year)" folder, and a file that
# repeats it followed by space-hyphen-space plus a quality label. Jellyfin's
# multiple-versions feature requires exactly that separator, and Radarr's default
# used a bare space - so this fixture is what stops that regressing.
#
# The provider-id form ("[imdbid-tt...]") is part of the convention but is
# deliberately NOT used here: a fake id would exercise Jellyfin's remote metadata
# lookup and make the check network-dependent.
#
# TWO files are written into one folder, because that is the only shape that
# actually discriminates. Measured against Jellyfin 10.11.11:
#   "Title (Year) - 480p" + "Title (Year) - 720p"  -> 1 item, 2 media sources
#   "Title (Year) 480p"   + "Title (Year) 720p"    -> 2 items, same film twice
# A single-file fixture passes under either convention and would prove nothing.
FIXTURE_TITLE="Portability Fixture"
FIXTURE_YEAR="2000"
FIXTURE_DIR="${FIXTURE_TITLE} (${FIXTURE_YEAR})"
FIXTURE_FILE_A="${FIXTURE_TITLE} (${FIXTURE_YEAR}) - 480p.mp4"
FIXTURE_FILE_B="${FIXTURE_TITLE} (${FIXTURE_YEAR}) - 720p.mp4"

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

  # Anything written through "compose exec" is owned by root on the host, so a
  # plain rm cannot remove it. Borrow a container to clear the contents, then
  # remove the directory itself (mktemp made it, so it is ours).
  #
  # Never silently swallow this: an earlier version did, and leaked one ~176K
  # workspace per run with no indication anything was wrong.
  if ! rm -rf "$WORKDIR" 2>/dev/null; then
    docker run --rm -v "${WORKDIR}:/w" alpine:3 \
      sh -c 'rm -rf /w/* /w/.[!.]* 2>/dev/null; true' >/dev/null 2>&1 || true
    rm -rf "$WORKDIR" 2>/dev/null || true
  fi
  [ -d "$WORKDIR" ] && printf '  \033[33mNOTE\033[0m leftover workspace not removed: %s\n' "$WORKDIR" >&2
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
RADARR_API_KEY=${RADARR_API_KEY}
SONARR_API_KEY=${SONARR_API_KEY}
JELLYFIN_ADMIN_USER=${ADMIN_USER}
JELLYFIN_ADMIN_PASSWORD=${ADMIN_PASS}
EOF
pass "built .env from .env.example with MEDIA_ROOT=${MEDIA_ROOT}"

dc() { docker compose -p "$PROJECT" -f "${WORKDIR}/compose.yaml" --env-file "${WORKDIR}/.env" "$@"; }

dc config --quiet || fail "compose.yaml does not parse, or a variable is unresolved"
pass "compose.yaml parses with every variable resolved"

# --- 3. step two of three ---------------------------------------------------
step "docker compose up -d"

dc up -d --quiet-pull >/dev/null 2>&1 || fail "'docker compose up -d' failed"
pass "stack started"

# --- 3b. step three of three ------------------------------------------------
step "scripts/seed.sh"

# The seed owns readiness, so the harness no longer waits separately. Its probes
# are the readiness-not-liveness ones issue #6 established: Jellyfin serves
# HTTP 200 on "/" while every API call still answers 503 "Jellyfin Server is
# loading", so anything polling "/" passes too early.
"${REPO_ROOT}/scripts/seed.sh" --env-file "${WORKDIR}/.env" \
  || fail "the seed failed on a blank host - see its output above"
pass "seed applied this repo's conventions to a blank host"

# Running it again must be a no-op, and that is TWO assertions in one:
#   - idempotence, demonstrated rather than claimed in a comment
#   - the running stack still matches seed/conventions.json, because
#     converge-or-refuse means the seeder IS the drift checker
# A stack that had drifted would exit 1 here with the differences printed.
SEED_AGAIN="$(mktemp -t seed-again-XXXXXX)"
if "${REPO_ROOT}/scripts/seed.sh" --env-file "${WORKDIR}/.env" >"$SEED_AGAIN" 2>&1; then
  grep -q 'ALREADY SEEDED' "$SEED_AGAIN" \
    || { cat "$SEED_AGAIN" >&2; fail "second seed run exited 0 but did not report a no-op"; }
  grep -q 'SET ' "$SEED_AGAIN" \
    && { cat "$SEED_AGAIN" >&2; fail "second seed run WROTE something - the seed is not idempotent"; }
  pass "second seed run is a no-op: idempotent, and the stack matches the data file"
else
  cat "$SEED_AGAIN" >&2
  rm -f "$SEED_AGAIN"
  fail "second seed run did not exit 0 - the stack does not match seed/conventions.json"
fi
rm -f "$SEED_AGAIN"

# --- 3c. converge or REFUSE -------------------------------------------------
step "The seed refuses a host that disagrees"

# The branch the two runs above cannot reach. They prove "blank -> seeded" and
# "already matches -> no-op"; neither touches the case the rule exists for, which
# is a host carrying a value a human deliberated. docs/library-layout.md calls a
# change to these values a migration rather than an edit, so a seed that quietly
# overwrote one would be the worst failure this repo has, and until now nothing
# would have caught it.
#
# Perturb, assert the refusal, then --force back so the rest of the harness runs
# against a conforming stack.
NAMING_URL="http://127.0.0.1:${RADARR_PORT}/api/v3/config/naming"
radarr_fmt() {
  curl -s -H "X-Api-Key: ${RADARR_API_KEY}" "$NAMING_URL" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["standardMovieFormat"])'
}

# Read the declared value rather than restating it, for the same reason the
# library block below does: a second copy of a value in this file is a second
# source of truth that rots.
DECLARED_FMT=$(python3 -c '
import json, sys
print(json.load(open(sys.argv[1]))["radarr"]["naming"]["standardMovieFormat"])
' "${REPO_ROOT}/seed/conventions.json")

BEFORE_FMT=$(radarr_fmt)
[ "$BEFORE_FMT" = "$DECLARED_FMT" ] \
  || fail "precondition failed: radarr's format is '${BEFORE_FMT}', expected the declared '${DECLARED_FMT}'"

# Valid, and deliberately so. Radarr VALIDATES naming formats and answers 400 to
# one it does not like, which silently leaves the value untouched - a first
# version of this test perturbed nothing and "passed" while proving nothing. The
# assertion below is what stops that recurring.
PERTURBED_FMT='{Movie Title} ({Release Year}) - {Quality Full}'
curl -s -H "X-Api-Key: ${RADARR_API_KEY}" "$NAMING_URL" \
  | python3 -c '
import json, sys
cfg = json.load(sys.stdin)
cfg["standardMovieFormat"] = sys.argv[1]
json.dump(cfg, sys.stdout)
' "$PERTURBED_FMT" > "${WORKDIR}/naming.json"

put_code=$(curl -s -o "${WORKDIR}/naming.out" -w '%{http_code}' -X PUT \
  -H "X-Api-Key: ${RADARR_API_KEY}" -H 'Content-Type: application/json' \
  --data-binary @"${WORKDIR}/naming.json" "${NAMING_URL}/1")
case "$put_code" in
  2*) : ;;
  *)  fail "could not perturb radarr's naming config: HTTP ${put_code} - $(head -c 200 "${WORKDIR}/naming.out")" ;;
esac
[ "$(radarr_fmt)" = "$PERTURBED_FMT" ] \
  || fail "the perturbation did not take - this test would prove nothing, so it fails loudly instead"
pass "perturbed radarr's standardMovieFormat, as a human changing it by hand would"

REFUSE_OUT="$(mktemp -t seed-refuse-XXXXXX)"

# "cmd || rc=$?" and not "if cmd; then ... fi; rc=$?" - the latter captures the
# status of the IF, which is 0 when the condition was false, so the exit code
# being asserted would never be the seed's.
refuse_rc=0
"${REPO_ROOT}/scripts/seed.sh" --env-file "${WORKDIR}/.env" >"$REFUSE_OUT" 2>&1 || refuse_rc=$?

case "$refuse_rc" in
  0) cat "$REFUSE_OUT" >&2; rm -f "$REFUSE_OUT"
     fail "the seed exited 0 against a host that disagrees - it should have refused" ;;
  1) : ;;
  *) cat "$REFUSE_OUT" >&2; rm -f "$REFUSE_OUT"
     fail "the seed exited ${refuse_rc} on disagreement, expected 1 (2 means it failed rather than refused)" ;;
esac
grep -q 'REFUSED' "$REFUSE_OUT" \
  || { cat "$REFUSE_OUT" >&2; rm -f "$REFUSE_OUT"; fail "the seed exited 1 without reporting a refusal"; }
grep -q 'standardMovieFormat' "$REFUSE_OUT" \
  || { cat "$REFUSE_OUT" >&2; rm -f "$REFUSE_OUT"; fail "the refusal did not name the value that differs"; }
rm -f "$REFUSE_OUT"

# The assertion that actually matters. Exiting 1 is worth nothing if it wrote
# first: what is being protected is the human's value, not the exit code.
[ "$(radarr_fmt)" = "$PERTURBED_FMT" ] \
  || fail "the seed REFUSED but wrote anyway - radarr's format is now '$(radarr_fmt)'"
pass "refused with exit 1, named the difference, and wrote nothing"

"${REPO_ROOT}/scripts/seed.sh" --env-file "${WORKDIR}/.env" --force >/dev/null 2>&1 \
  || fail "'--force' did not converge the host it had just refused"
[ "$(radarr_fmt)" = "$DECLARED_FMT" ] \
  || fail "'--force' exited 0 but radarr's format is '$(radarr_fmt)', not the declared '${DECLARED_FMT}'"
pass "'--force' converged the same host deliberately"

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
dc exec -T jellyfin mkdir -p "/data/movies/${FIXTURE_DIR}" \
  || fail "could not create the fixture directory under /data (bind mount permissions?)"

for f in "$FIXTURE_FILE_A" "$FIXTURE_FILE_B"; do
  dc exec -T jellyfin /usr/lib/jellyfin-ffmpeg/ffmpeg \
    -f lavfi -i testsrc=duration=5:size=640x480:rate=24 \
    -f lavfi -i sine=frequency=440:duration=5 \
    -c:v libx264 -preset ultrafast -pix_fmt yuv420p -c:a aac -shortest \
    -y "/data/movies/${FIXTURE_DIR}/${f}" >/dev/null 2>&1 \
    || fail "ffmpeg could not write '${f}' into the library"
done

host_file="${MEDIA_ROOT}/movies/${FIXTURE_DIR}/${FIXTURE_FILE_A}"
[ -s "$host_file" ] || fail "fixture is not visible on the host at ${host_file} - the bind mount is not working"
pass "fixture written and visible on the host ($(du -h "$host_file" | cut -f1))"

# --- 6. Jellyfin round trip -------------------------------------------------
step "Jellyfin round trip"

AUTH_HDR='MediaBrowser Client="portability-check", Device="ci", DeviceId="portability-check", Version="1.0.0"'
JF="http://127.0.0.1:${JELLYFIN_PORT}"

# The startup wizard and the library definitions are NOT created here. The seed
# already ran both, and duplicating them was the whole defect issue #7 named: the
# bootstrap that ships to users would be the one CI never exercises. This section
# authenticates as the admin the seed created and asserts what it produced.
TOKEN=$(curl -sf -X POST "${JF}/Users/AuthenticateByName" \
  -H 'Content-Type: application/json' \
  -H "X-Emby-Authorization: ${AUTH_HDR}" \
  -d "{\"Username\":\"${ADMIN_USER}\",\"Pw\":\"${ADMIN_PASS}\"}" \
  | grep -o '"AccessToken":"[^"]*"' | cut -d'"' -f4)
[ -n "${TOKEN:-}" ] || fail "authentication returned no access token"
pass "authenticated as ${ADMIN_USER}"

jf() { curl -s -H "X-Emby-Token: ${TOKEN}" -H "X-Emby-Authorization: ${AUTH_HDR}" "$@"; }

# BOTH libraries, not just Movies. The harness used to create only Movies and so
# proved nothing about the TV root, which the seed now defines.
#
# The names and paths are READ FROM the data file rather than written out again
# here. The second seed run above is already the authoritative conformance
# assertion - converge-or-refuse means a no-op proves every declared value
# matches. This block exists so the CI log shows a human the libraries by name
# instead of only "ALREADY SEEDED", and deriving it keeps that convenience from
# quietly becoming a second copy of the values.
# Parsed, never pattern-matched. These services do not agree on whitespace in
# their JSON - Jellyfin answers compact, Radarr answers pretty-printed - so a
# glob for '"path":"/data/movies"' passes on one and fails on the other for a
# reason that has nothing to do with what is being asserted.
CONVENTIONS="${REPO_ROOT}/seed/conventions.json"
if out=$(jf "${JF}/Library/VirtualFolders" | python3 -c '
import json, sys
live = json.load(sys.stdin)
missing = []
for lib in json.load(open(sys.argv[1]))["jellyfin"]["libraries"]:
    hit = next((f for f in live if f.get("Name") == lib["name"]), None)
    if hit is None:
        missing.append("no Jellyfin library named %r" % lib["name"])
    elif lib["path"] not in (hit.get("Locations") or []):
        missing.append("Jellyfin library %r does not include %s (has %s)"
                       % (lib["name"], lib["path"], hit.get("Locations")))
    else:
        print("Jellyfin library %r present at %s" % (lib["name"], lib["path"]))
if missing:
    sys.exit("; ".join(missing))
' "$CONVENTIONS" 2>&1); then
  printf '%s\n' "$out" | while IFS= read -r line; do pass "$line"; done
else
  fail "the seed did not leave the declared Jellyfin libraries: ${out}"
fi

ITEM_JSON=""
for i in $(seq 1 60); do
  ITEM_JSON=$(jf "${JF}/Items?Recursive=true&IncludeItemTypes=Movie&Limit=10&Fields=ProductionYear,MediaSourceCount" || true)
  case "$ITEM_JSON" in *'"Id"'*) break ;; esac
  jf -X POST "${JF}/Library/Refresh" >/dev/null 2>&1 || true
  sleep 2
done
case "$ITEM_JSON" in
  *'"Id"'*) : ;;
  *) fail "Jellyfin never indexed the fixture - it can see the mount but not read the library" ;;
esac

ITEM_ID=$(printf '%s' "$ITEM_JSON" | grep -o '"Id":"[^"]*"' | head -1 | cut -d'"' -f4)
ITEM_COUNT=$(printf '%s' "$ITEM_JSON" | grep -o '"Type":"Movie"' | wc -l | tr -d ' ')
ITEM_YEAR=$(printf '%s' "$ITEM_JSON" | grep -o '"ProductionYear":[0-9]*' | head -1 | cut -d: -f2)
SOURCE_COUNT=$(printf '%s' "$ITEM_JSON" | grep -o '"MediaSourceCount":[0-9]*' | head -1 | cut -d: -f2)
pass "fixture indexed by Jellyfin (item ${ITEM_ID}) after ~$((i*2))s"

# WF-003: assert the naming convention, not merely that something was indexed.
# Both assertions below were measured to fail under the wrong convention.
[ "$ITEM_YEAR" = "$FIXTURE_YEAR" ] \
  || fail "year parsed as '${ITEM_YEAR}', expected '${FIXTURE_YEAR}' - the 'Title (Year)' folder convention is not being honoured"

# The discriminating one. Two labelled files in one folder must collapse into a
# single movie with two versions. Under a bare-space separator Jellyfin indexes
# them as two separate movies and the library shows the same film twice.
[ "${ITEM_COUNT:-0}" = "1" ] \
  || fail "expected 1 movie item, found ${ITEM_COUNT} - the ' - <label>' version convention is not being honoured, so the same film is listed more than once"
[ "${SOURCE_COUNT:-0}" = "2" ] \
  || fail "expected 2 media sources on the movie, found ${SOURCE_COUNT:-none} - the two quality variants did not group as versions"
pass "convention honoured: 1 movie, year ${ITEM_YEAR}, ${SOURCE_COUNT} versions grouped"

# The assertion that actually matters: bytes come back out.
BYTES=$(jf -o /dev/null -w '%{size_download}' \
  -H 'Range: bytes=0-65535' \
  "${JF}/Videos/${ITEM_ID}/stream?static=true" || echo 0)
[ "${BYTES:-0}" -gt 1024 ] \
  || fail "streaming returned ${BYTES} bytes - Jellyfin indexed the file but cannot serve it"
pass "streamed ${BYTES} bytes back from the library"

# --- 7. the *arr root folders ------------------------------------------------
step "Radarr and Sonarr root folders"

# Same rationale as the Jellyfin library block: the seed's no-op run already
# proved conformance, and the paths are read from the data file rather than
# repeated. This is here because "the TV root is configured" is a claim the
# harness previously could not make at all, and it should be visible.
for svc in radarr sonarr; do
  case "$svc" in
    radarr) port="$RADARR_PORT"; key="$RADARR_API_KEY" ;;
    sonarr) port="$SONARR_PORT"; key="$SONARR_API_KEY" ;;
  esac
  if out=$(curl -s -H "X-Api-Key: ${key}" "http://127.0.0.1:${port}/api/v3/rootfolder" \
    | python3 -c '
import json, sys
live = {r["path"] for r in json.load(sys.stdin)}
svc = sys.argv[2]
missing = [p for p in json.load(open(sys.argv[1]))[svc]["rootFolders"] if p not in live]
for p in sorted(set(json.load(open(sys.argv[1]))[svc]["rootFolders"]) & live):
    print("%s root folder %s" % (svc, p))
if missing:
    sys.exit("%s is missing root folder(s) %s; it has %s"
             % (svc, missing, sorted(live)))
' "$CONVENTIONS" "$svc" 2>&1); then
    printf '%s\n' "$out" | while IFS= read -r line; do pass "$line"; done
  else
    fail "$out"
  fi
done
