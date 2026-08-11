---
id: 003
title: Decide the library layout both Jellyfin and the arr apps accept
labels: [wayfinder:grilling]
state: open
assignee: null
blocked_by: []
---

## Question

Jellyfin infers metadata from folder and file naming. Radarr and Sonarr *impose*
naming through their own rename engines. Point them at the same tree without
agreeing a convention first and the `*arr` apps will rename files out from under
Jellyfin's index, or Jellyfin will fail to match titles it should.

What is the committed convention?

- Folder shape. Jellyfin's documented preference is
  `Movies/Title (Year)/Title (Year).ext` and
  `Shows/Title (Year)/Season 01/Title - S01E01.ext`. Do Radarr's and Sonarr's
  rename templates get configured to emit exactly that, or does Jellyfin get
  configured to tolerate whatever the `*arr` defaults produce?
- One root or two. `/srv/media/movies` and `/srv/media/tv` as separate roots, or
  a single root with subtrees? This decides how many Jellyfin libraries exist and
  what each `*arr` app claims as its root folder.
- Path identity across containers. If Radarr sees `/data/movies` and Jellyfin
  sees `/movies`, imports still work but hardlinking and atomic moves do not.
  Confirm the single-path decision from ticket 001 survives contact with the
  `*arr` import flow.
- Ownership of the tree. Which process is authoritative for naming - the `*arr`
  apps, or the human dropping files in by hand? Both writing to one tree with
  different conventions is the failure mode this ticket exists to prevent.

This is a genuine architecture decision under the map's standing preferences, so
it gets resolved by presenting concrete options with trade-offs, not by picking
one unilaterally.
