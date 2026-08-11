---
id: 001
title: Stand up the LAN stack on the host
labels: [wayfinder:task]
state: closed
assignee: luken
blocked_by: []
---

## Question

Nothing to decide - the shape is fixed by the charting session. This is the
tracer bullet that makes the rest of the map testable, and it is blocked on
nothing.

Build and bring up the stack:

- `compose.yaml` with `jellyfin`, `radarr`, `sonarr` from `lscr.io/linuxserver/*`.
- `.env.example` (committed) carrying `MEDIA_ROOT`, `PUID`, `PGID`, `TZ`.
  `.env` itself is gitignored.
- Bind mounts: `./config/<service>` per service, `${MEDIA_ROOT}` into all three.
  Radarr and Sonarr must see the library at the *same container path* Jellyfin
  does, or hardlinks and renames break later.
- `.gitignore` covering `.env`, `config/`, and `docker-compose.override.yml`.
- No `/dev/dri`, no host-network hacks, no ports beyond 8096 / 7878 / 8989.
- `/srv/media` created on the host with `movies/` and `tv/` subtrees owned by
  the `PUID`/`PGID` the containers run as.

Resolved when all three web UIs answer on the LAN IP and the containers survive
a `docker compose down && docker compose up -d` cycle with config intact.

Per the map's Notes: paste the real `docker compose ps` and HTTP status output.
Do not report green from inspection.

## Resolution

The stack is up and both acceptance conditions are met with real output.

**All three UIs answer on the LAN IP:**

```
jellyfin http://192.168.100.6:8096/ -> HTTP 200
radarr   http://192.168.100.6:7878/ -> HTTP 200
sonarr   http://192.168.100.6:8989/ -> HTTP 200
```

**Survives `docker compose down && docker compose up -d` with config intact.**
Proven by identity rather than by inspection - Jellyfin's server Id is generated
once on first boot, so its survival means the bind mount really persisted:

```
before: "Id":"47a8ee3f0f78426b8c4df4f7259f8aac"   checksum 8be05f83cc0c6909102b8d2fa4b7d50c
after:  "Id":"47a8ee3f0f78426b8c4df4f7259f8aac"   checksum 8be05f83cc0c6909102b8d2fa4b7d50c
```

### What was built

- `compose.yaml` - three LinuxServer services, `restart: unless-stopped`, no
  hardware assumptions, ports 8096 / 7878 / 8989 only.
- `.env.example` committed, `.env` gitignored, `MEDIA_ROOT=/srv/media`,
  `PUID=1000`, `PGID=1000`, `TZ=America/Santiago`.
- `.gitignore` covering `.env`, `config/`, and both override-file spellings.
- `/srv/media/{movies,tv}` owned `1000:1000` (needed one sudo from the human;
  the agent has no passwordless sudo on this host).

### Facts later tickets depend on

- **`${MEDIA_ROOT}` mounts at `/data` in all three containers**, identically.
  Verified: each container lists `movies tv` under `/data`. Do not diverge these
  or the `*arr` import path loses hardlinking and atomic moves. Bears on 003.
- **`PUID`/`PGID` work correctly.** Every file under `config/` is owned
  `luken:luken (1000:1000)` - no root-owned files landed in the repo tree, which
  was the main risk of choosing bind mounts over named volumes.
- **Ports were free and no host networking was needed.** Discovery (`7359/udp`)
  deliberately not exposed; raw-IP addressing per Q10. If the WebOS client turns
  out to need it, that surfaces in 002.
- **Host `render` group is gid 110** - needed by 007 for `/dev/dri` permissions.
- **Jellyfin's first-run setup wizard has not been completed.** The service
  answers HTTP 200 but has no admin user and no libraries defined. This is human
  work and belongs to 002; that ticket has been updated to include it.
- **Images resolved to `latest` at this moment**: jellyfin `32cc24a646a4`,
  radarr `5a29acd9cee5`, sonarr `de227c8e8683`. A clean host tomorrow gets
  different images. This graduated the pinning fog into ticket 008.
