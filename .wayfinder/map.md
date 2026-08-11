---
labels: [wayfinder:map]
---

# Map: Portable LAN media server (Jellyfin + Radarr + Sonarr)

## Destination

A committed git repo at `~/Sandbox/media-server` that stands up Jellyfin, Radarr
and Sonarr with `docker compose up -d` on any clean Ubuntu 24.04 machine, serving
a LAN-only library rooted at an injected `MEDIA_ROOT`, and reachable from a WebOS
LG TV's Jellyfin client.

Done means: a clean Ubuntu box plus `git clone` plus one command yields a working
stack, and that claim has been tested rather than asserted.

## Notes

**Domain**: self-hosted media infrastructure. Ubiquitous language - *library*
(the media tree Jellyfin indexes), *root folder* (an `*arr` term for where it
files media), *host* (the machine running the stack), *stack* (the three
services plus their compose wiring).

**Skills every session should consult**: `/grilling` and `/domain-modeling` by
default; `/research` for third-party facts (WebOS client codec support,
LinuxServer image env contracts); `/prototype` for compose shapes worth reacting
to before committing.

**Standing preferences for this effort** (from the dev's global CLAUDE.md):
- Do not decide architecture. Present concrete options with trade-offs and let
  the human pick.
- Prove, don't claim. Paste real command output; never report green from
  inspection.
- Weigh by simplicity, robustness and long-term maintainability, not by how
  cheap something is to build.
- No em dashes in prose. Plain dashes.

**Effort-specific**: this map is planning-plus-execution. The `task` tickets here
genuinely build and verify the stack, because the destination is a working repo
rather than a document. Decision tickets still resolve one per session.

## Settled at charting

Fixed by the charting grilling session; these constrain every ticket below and
are not re-litigated without a superseding decision.

- **Artifact is a committed repo**, not a running instance. `docker compose up -d`
  on a clean Ubuntu box is the acceptance shape.
- **Portable means config-portable.** The repo reconstitutes the stack on any
  host; the library stays behind. `MEDIA_ROOT` is a single injected variable in
  `.env`, which makes a travelling external drive a cheap later graduation.
- **Library lives at `/srv/media`** on the host root filesystem. 314G free, shared
  with the OS. Known ceiling, known graduation path.
- **Images are LinuxServer.io** (`lscr.io/linuxserver/*`) for one uniform
  `PUID`/`PGID`/`TZ` convention across all three services.
- **Config persists as bind mounts** under `./config/<service>`, gitignored.
  Named volumes were rejected: they are opaque and defeat the portability claim.
- **Radarr and Sonarr ship in the stack** wired to the library, with indexers and
  download client left unconfigured.
- **No `/dev/dri` in the base compose.** Hardware transcoding is opt-in per host
  via `docker-compose.override.yml`, so the base file stays hardware-agnostic.
- **The TV addresses the host by raw IP.** DHCP reservation is a host concern and
  stays out of the repo.
- **The laptop is a stand-in host.** Laptop-specific fixes (lid-suspend
  inhibition, Wi-Fi power management) are tactical and uncommitted.

## Decisions so far

<!-- one line per closed ticket -->

- [Stand up the LAN stack on the host](tickets/001-stand-up-lan-stack.md) - Stack
  is up and verified: all three UIs answer HTTP 200 on `192.168.100.6`, and
  config survives a down/up cycle (proven by Jellyfin's first-boot server Id
  persisting). `${MEDIA_ROOT}` mounts at `/data` identically in all three
  containers; `PUID`/`PGID` confirmed working with no root-owned files. Jellyfin's
  setup wizard is still unrun - moved into ticket 002.
- [Decide what portable must prove and how it gets tested](tickets/004-what-portable-must-prove.md) -
  Acceptance criterion is now `scripts/verify-portability.sh` exiting 0 on a
  GitHub Actions `ubuntu-24.04` runner. Docker is an asserted prerequisite, never
  installed. The test asserts a full round trip against a self-generated ffmpeg
  fixture (synthesise, index, stream bytes back), not liveness. **Green on CI**
  (run 31533312916) against Ubuntu 24.04.4 with a different Docker version than
  the dev host, so the destination's portability claim now holds with evidence.
  Writing it found three real defects in 001's compose file - hardcoded
  `container_name`, fixed host ports, and liveness mistaken for readiness - all
  fixed.
- [Decide the image pinning strategy](tickets/008-image-pinning-strategy.md) -
  Pin `<version>@sha256:<digest>`, update via Renovate PRs (one per service,
  majors need approval), gate merges on the portability check. Reproducibility
  and currency both kept rather than traded. A bare version tag would not have
  been reproducible: LinuxServer rebuilds tags in place and jellyfin's `latest`
  already moved `ubu2404` -> `ubu2604`. CI green on the pinned commit (run
  31533869813). Renovate install and branch protection are not done - they need
  a human and became [Enable the update pipeline on GitHub](tickets/009-enable-the-update-pipeline.md).

## Not yet specified

In scope, but not yet sharp enough to ticket. Graduates as the frontier advances.

- **Storage graduation.** 314G is roughly 15-30 movies at good quality. When it
  fills, the library moves to an external drive or NAS. The `MEDIA_ROOT` variable
  is the seam, but mount reliability, permissions across hosts, and what happens
  to `*arr` root folders when the path changes are all unsketched.
- **Backup and restore of stack state.** `./config/` is gitignored, so Jellyfin's
  metadata, users, watch progress and the `*arr` databases currently travel with
  nothing. Overlaps with the "what travels" ticket but is broader than it.
- **Second user account.** The girlfriend is a viewer, which implies user
  management, per-user watch state, and possibly parental/library scoping. Not
  yet clear whether this is one Jellyfin setting or a real decision.
- **Subtitles.** Sourcing, embedding, and whether the WebOS client renders the
  formats in play. Likely a research ticket once real files are in the library.
- **Observability.** Whether this stack needs logs and health beyond
  `docker compose ps`, and if so what.

<!-- graduated: "Update and pin strategy" became ticket 008 when 001 made the
     floating-tag problem concrete. -->


## Out of scope

Ruled beyond this destination. Never graduates; returns only as a fresh effort.

- **Remote / internet exposure.** The dev named this explicitly as a follow-up
  effort. Reverse proxy, TLS, auth hardening, VPN and DNS all live there.
- **Host-portable operation** (Q2c) - this literal laptop moving between networks
  as a server. Rejected in favour of config-portability; it drags in roaming
  addresses, captive portals and power management for no gain against the stated
  destination.
- **Acquisition of copyrighted material the dev has not licensed.** The agent
  declined to help select or configure sources for this. See
  [Decide Radarr/Sonarr acquisition sources](tickets/006-arr-acquisition-sources.md)
  for what is and is not in play.
