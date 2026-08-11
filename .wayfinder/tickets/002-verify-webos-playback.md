---
id: 002
title: Verify playback on the WebOS TV
labels: [wayfinder:task]
state: open
assignee: null
blocked_by: [001]
---

## Question

HITL - needs a human at the TV with the remote.

Prove the whole chain end to end: a file on `/srv/media`, indexed by Jellyfin,
playing on the LG WebOS Jellyfin client over Wi-Fi.

The file is supplied by the dev and must be one they hold legitimately. The
stack is indifferent to which file it is; a freely-licensed 4K H.264 title is
the better *test* because a known-good encode separates "my config is wrong"
from "my file is bad".

Checklist for the human:

0. **Complete Jellyfin's first-run setup wizard** at `http://192.168.100.6:8096`.
   Ticket 001 left the service answering HTTP 200 with no admin user and no
   libraries - that is human work, not compose work. Create the admin account and
   add a Movies library pointing at `/data/movies` (the *container* path, not
   `/srv/media/movies`).
1. Drop the file at `/srv/media/movies/<Title> (<Year>)/<Title> (<Year>).<ext>`.
2. Trigger a Jellyfin library scan; confirm the title appears with metadata.
3. On the TV, add server `http://192.168.100.6:8096`.
4. Play. Record whether it **direct plays** or transcodes (Jellyfin dashboard
   shows this live) - a transcode on this hardware without `/dev/dri` mounted is
   CPU-only and is the signal that ticket 007 matters.

Resolved when the title plays on the TV. The answer records: direct play vs
transcode, any codec the client refused, and observed Wi-Fi adequacy.

Note the two known host-level failure modes, both out-of-repo per the map:
the laptop suspending on lid close mid-playback, and the DHCP lease on
`192.168.100.6` moving out from under the TV's saved server entry.
