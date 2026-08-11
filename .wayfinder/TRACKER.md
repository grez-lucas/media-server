# Tracker conventions (local-markdown)

No external issue tracker was configured for this repo, so wayfinder uses the
local-markdown fallback. This file is the tracker doc.

## Layout

- `.wayfinder/map.md` - the map. Exactly one, labelled `wayfinder:map`.
- `.wayfinder/tickets/NNN-<slug>.md` - child tickets of the map. `NNN` is the
  ticket id and is never reused.

## Ticket frontmatter

```yaml
---
id: NNN
title: <the ticket name - always refer to tickets by this, never by id alone>
labels: [wayfinder:<research|prototype|grilling|task>]
state: open | closed
assignee: <who claimed it, or null>
blocked_by: [NNN, NNN]   # ids that must be closed first
---
```

## Wayfinding operations

- **Create map**: write `.wayfinder/map.md`.
- **Create ticket**: write `.wayfinder/tickets/NNN-<slug>.md` with frontmatter above.
- **Claim a ticket**: set `assignee` before doing any work. An open ticket with
  `assignee: null` is unclaimed.
- **Blocking**: `blocked_by` list. A ticket is unblocked when every id in it has
  `state: closed`.
- **Frontier query**: `state: open` AND `assignee: null` AND every `blocked_by`
  id closed. Run `.wayfinder/frontier.sh` to list it.
- **Resolve**: append a `## Resolution` section to the ticket body, set
  `state: closed`, then append a one-line pointer to the map's Decisions so far.
