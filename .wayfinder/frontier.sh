#!/usr/bin/env bash
# Lists the wayfinder frontier from GitHub Issues: open, unassigned tickets whose
# blocking issues are all closed.
#
# Usage: .wayfinder/frontier.sh [--all]
set -euo pipefail

REPO="${WAYFINDER_REPO:-grez-lucas/media-server}"
MAP=$(gh issue list --repo "$REPO" --label wayfinder:map --state all --limit 1 --json number --jq '.[0].number')
[ -n "$MAP" ] || { echo "no issue labelled wayfinder:map in $REPO" >&2; exit 1; }

show_all="${1:-}"

gh api "repos/${REPO}/issues/${MAP}/sub_issues" --paginate \
  --jq '.[] | {number, title, state, assignees: [.assignees[].login], labels: [.labels[].name]}' \
| while read -r row; do
    num=$(printf '%s' "$row" | python3 -c 'import json,sys;print(json.load(sys.stdin)["number"])')
    title=$(printf '%s' "$row" | python3 -c 'import json,sys;print(json.load(sys.stdin)["title"])')
    state=$(printf '%s' "$row" | python3 -c 'import json,sys;print(json.load(sys.stdin)["state"])')
    who=$(printf '%s' "$row" | python3 -c 'import json,sys;print(",".join(json.load(sys.stdin)["assignees"]))')
    kind=$(printf '%s' "$row" | python3 -c 'import json,sys;print(next((l.split(":")[1] for l in json.load(sys.stdin)["labels"] if l.startswith("wayfinder:")),"?"))')

    open_blockers=$(gh api "repos/${REPO}/issues/${num}/dependencies/blocked_by" \
      --jq '[.[] | select(.state=="open") | "#\(.number)"] | join(" ")' 2>/dev/null || echo "")

    if [ "$state" = "closed" ]; then status="CLOSED  "
    elif [ -n "$open_blockers" ]; then status="BLOCKED "
    elif [ -n "$who" ]; then status="CLAIMED "
    else status="FRONTIER"
    fi

    if [ "$show_all" = "--all" ] || [ "$status" = "FRONTIER" ]; then
      printf '%s #%-3s %-58s [%s]' "$status" "$num" "${title:0:58}" "$kind"
      [ -n "$open_blockers" ] && printf ' blocked by: %s' "$open_blockers"
      [ -n "$who" ] && printf ' @%s' "$who"
      printf '\n'
    fi
  done
