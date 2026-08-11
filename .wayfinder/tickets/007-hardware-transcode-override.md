---
id: 007
title: Add the hardware transcode override for this host
labels: [wayfinder:task]
state: open
assignee: null
blocked_by: [001, 002]
---

## Question

Nothing to decide - the mechanism was settled at charting (opt-in per host via
`docker-compose.override.yml`, never in the base compose). This ticket is the
work of building and proving it.

The host has an Intel Arc iGPU at `/dev/dri/renderD128` (Core Ultra 9 185H),
which is strong at QuickSync and is the right transcode path here. The discrete
RTX 4050 is the wrong one: NVENC needs the container toolkit and a much heavier
setup for no gain over QSV on this workload.

The work:

- Write `docker-compose.override.yml.example` (committed) mounting `/dev/dri`
  into the Jellyfin container with the right group permissions - `render` group
  gid on the host has to be granted inside the container or the device is
  present but unusable.
- Enable QSV in Jellyfin's transcoding settings and record which codecs get
  hardware decode and encode.
- Confirm the base `compose.yaml` still comes up on a host with no `/dev/dri`,
  since that is the whole point of keeping the override separate.

Blocked by ticket 002 deliberately: 002 records whether the TV direct plays or
transcodes. If it direct plays everything the dev cares about, this ticket may be
worth deferring rather than doing, and that evidence should exist before the work
starts.

Resolved with real evidence: a forced transcode showing hardware acceleration
active in the Jellyfin dashboard, plus CPU usage compared against the software
path.
