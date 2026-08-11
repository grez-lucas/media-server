---
id: 006
title: Decide Radarr and Sonarr acquisition sources
labels: [wayfinder:task]
state: open
assignee: null
blocked_by: []
---

## Question

HITL, and this one is the dev's alone to resolve.

Radarr and Sonarr ship in the stack unconfigured (settled at charting). They are
managers, not sources: without an indexer and a download client they still
usefully rename, organise and monitor a library, but they fetch nothing.

What the dev decides here:

- Whether automated acquisition is configured at all, or whether the `*arr` apps
  run purely as library organisers over media added by hand. The second is a
  complete and coherent setup with no external dependency.
- If acquisition is configured: which indexers and which download client, and
  whether Prowlarr joins the stack as the indexer manager rather than
  configuring indexers twice.

**Agent boundary, recorded so later sessions do not relitigate it:** the agent
declined to help select or configure sources for obtaining copyrighted material
the dev has not licensed. It will wire whatever legitimate configuration the dev
lands on - compose entries for a download client, Prowlarr, path and permission
alignment, `*arr` connection settings - but the choice and provisioning of
sources sits with the dev.

Resolved when the dev states the direction. The answer records what was chosen
and any facts later tickets depend on: container names and ports to add, download
directory paths that must align with `MEDIA_ROOT` for hardlinking to work, and
where credentials live.
