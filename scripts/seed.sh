#!/usr/bin/env bash
#
# Applies this repo's conventions to a running stack - the third of the three
# steps the destination promises: git clone, docker compose up -d, scripts/seed.sh.
#
# The work is done by seed.py. This wrapper exists to ASSERT THE INTERPRETER and
# fail loudly, matching the "prerequisites, asserted, never installed" pattern
# scripts/verify-portability.sh uses for Docker. Python 3 is an assumption this
# repo makes about the host, so it gets checked at runtime rather than inherited.
#
# Usage: scripts/seed.sh [--force] [--env-file PATH] [--quiet]
# Exit:  0 converged or already converged
#        1 the host disagrees with seed/conventions.json and nothing was written
#        2 a prerequisite is missing, or the run failed
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

command -v python3 >/dev/null 2>&1 || {
  printf '\033[31mFAIL\033[0m python3 not found.\n' >&2
  printf '     It is a prerequisite of this repo, asserted here and never installed.\n' >&2
  printf '     On Ubuntu:  sudo apt-get install -y python3\n' >&2
  exit 2
}

# Only the standard library is used, but a 3.x that predates the syntax would
# fail with a traceback rather than a message. Check the version explicitly.
python3 - <<'PY' || exit 2
import sys
if sys.version_info < (3, 8):
    sys.stderr.write(
        "\033[31mFAIL\033[0m python3 is %s; this repo needs 3.8 or newer.\n"
        % ".".join(map(str, sys.version_info[:3]))
    )
    raise SystemExit(1)
PY

exec python3 "${REPO_ROOT}/scripts/seed.py" "$@"
