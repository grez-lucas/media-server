# Tracker conventions (GitHub Issues)

The wayfinder tracker for this repo is **GitHub Issues** on
`grez-lucas/media-server`. Issues are the source of truth. Nothing in this
directory duplicates them - a decision lives in exactly one place, its issue.

Migrated from the local-markdown fallback on 2026-08-11; the original files were
deleted rather than left as a second copy that would silently rot.

## Layout

| thing | where |
|---|---|
| the map | issue labelled `wayfinder:map` - currently [#2](https://github.com/grez-lucas/media-server/issues/2) |
| tickets | issues that are **native sub-issues** of the map |
| ticket type | label `wayfinder:` + `research` \| `prototype` \| `grilling` \| `task` |
| claim | GitHub assignee. Open + unassigned means unclaimed |
| blocking | native **issue dependencies** (`blocked_by`), not a body convention |
| resolution | a comment on the ticket, then close it, then index one line on the map |

GitHub supports sub-issues and dependencies natively here, so the frontier renders
in GitHub's own UI - the map shows a `4/9` sub-issue progress bar, and blocked
tickets show their blockers without opening anything.

## Wayfinding operations

Set `WAYFINDER_REPO` to override the repo; it defaults to `grez-lucas/media-server`.

**Frontier** (open, unassigned, all blockers closed):

```bash
.wayfinder/frontier.sh          # frontier only
.wayfinder/frontier.sh --all    # every ticket with its status
```

**Create a ticket** (child of the map):

```bash
url=$(gh issue create --title "<name>" --label "wayfinder:grilling" --body "## Question

<the decision this resolves>")
num=${url##*/}
iid=$(gh api repos/grez-lucas/media-server/issues/$num --jq .id)
gh api -X POST repos/grez-lucas/media-server/issues/2/sub_issues -F sub_issue_id=$iid
```

**Wire blocking** (`<blocked>` waits on `<blocker>`):

```bash
blocker_id=$(gh api repos/grez-lucas/media-server/issues/<blocker> --jq .id)
gh api -X POST repos/grez-lucas/media-server/issues/<blocked>/dependencies/blocked_by \
  -F issue_id=$blocker_id
```

**Claim** (before any work):

```bash
gh issue edit <num> --add-assignee @me
```

**Resolve**:

```bash
gh issue comment <num> --body-file resolution.md
gh issue close <num> --reason completed
gh issue edit 2 --body-file updated-map.md   # append one line to Decisions so far
```

**Rule out of scope** - close the issue and add a line to the map's *Out of scope*
section. It never lands in *Decisions so far*: that records the route walked, and a
scope boundary is not a step on it.

## Conventions

- **Refer to issues by name, not number.** `[Verify playback on the WebOS TV](url)`,
  never a bare `#4`. The number rides inside the link.
- **The map is an index.** One line per closed ticket, gisting the answer and
  linking. The detail stays in the ticket.
- **Ticket ids.** The GitHub issue number is the identity. Commit messages use the
  historical `WF-00N` ids from before the migration where they already exist; new
  work should reference the issue number.
