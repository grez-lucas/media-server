#!/usr/bin/env bash
# Lists the frontier: open, unclaimed tickets whose blockers are all closed.
# Usage: .wayfinder/frontier.sh [--all]
set -euo pipefail

cd "$(dirname "$0")/tickets"

field() { sed -n "s/^$2: *//p" "$1" | head -1; }

declare -A state
for f in *.md; do
  state["$(field "$f" id)"]="$(field "$f" state)"
done

show_all="${1:-}"

for f in *.md; do
  id="$(field "$f" id)"
  st="$(field "$f" state)"
  title="$(field "$f" title)"
  label="$(field "$f" labels | tr -d '[]')"
  assignee="$(field "$f" assignee)"
  blockers="$(field "$f" blocked_by | tr -d '[]' | tr ',' ' ')"

  open_blockers=""
  for b in $blockers; do
    [ "${state[$b]:-open}" != "closed" ] && open_blockers="$open_blockers $b"
  done

  if [ "$st" = "closed" ]; then
    status="CLOSED   "
  elif [ -n "$open_blockers" ]; then
    status="BLOCKED  "
  elif [ "$assignee" != "null" ] && [ -n "$assignee" ]; then
    status="CLAIMED  "
  else
    status="FRONTIER "
  fi

  if [ "$show_all" = "--all" ] || [ "$status" = "FRONTIER " ]; then
    printf '%s %s  %-58s [%s]' "$status" "$id" "$title" "$label"
    [ -n "$open_blockers" ] && printf ' blocked by:%s' "$open_blockers"
    printf '\n'
  fi
done
