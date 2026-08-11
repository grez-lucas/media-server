---
id: 005
title: Decide what travels with the repo so a new host reconstitutes state
labels: [wayfinder:grilling]
state: open
assignee: null
blocked_by: [001, 004]
---

## Question

`./config/` is gitignored, which means a `git clone` on a new host produces three
services with **no** users, no library definitions, no API keys, no `*arr`
databases, and no watch history. Everything gets reconfigured by hand through
three web UIs.

That is a defensible answer, but it is currently an accident of the bind-mount
decision rather than a choice. Portability is the headline requirement, so what
"portable" restores has to be named.

The spectrum:

- **Compose only.** Clone, `up -d`, reconfigure by hand. Simplest, honest, and
  the reconfiguration cost is paid every time.
- **Compose plus seeded config.** Commit minimal starting config (Jellyfin
  library definitions, `*arr` root folders and naming templates) so a new host
  boots opinionated rather than blank. Needs care: these files interleave
  settings with secrets and machine-specific ids.
- **Compose plus a backup/restore path.** The repo ships scripts that snapshot
  and rehydrate `./config/`, and the snapshots live outside git. Highest fidelity,
  most moving parts, and it introduces a restore procedure that itself needs
  testing.

Bearing on the decision:

- API keys and Jellyfin user credentials must never reach git regardless of which
  option wins. If config is seeded, the secret-bearing fields need a documented
  extraction seam.
- Ticket 004 fixes what the portability test asserts. If that test demands a
  streaming round trip on a clean host, "compose only" makes the test slow and
  manual, which pushes toward seeding.
- Watch progress and user accounts are the state a human actually misses. Whether
  those count as "the stack" or "the data" is the real question underneath this
  one.
