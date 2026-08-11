---
id: 004
title: Decide what portable must prove and how it gets tested
labels: [wayfinder:grilling]
state: closed
assignee: luken
blocked_by: []
---

## Question

The destination says "works on any clean Ubuntu 24.04 machine". That claim is
currently untested and untestable - there is one machine, and it is the machine
the stack was built on. Under the map's "prove, don't claim" standing preference,
an unverifiable acceptance criterion is not an acceptance criterion.

What counts as proof, and what runs it?

- **What is the clean host?** A throwaway VM (multipass, libvirt, cloud
  instance), a container-in-container harness, or a genuine second physical
  machine? Each trades fidelity against how often the test can actually run.
- **How clean is clean?** Docker preinstalled or not? If the repo must also
  bootstrap Docker on a bare Ubuntu image, that is a materially larger artifact
  than a compose file, and it should be an explicit decision rather than
  something discovered halfway.
- **What does the test assert?** Three containers reach `running`? All three UIs
  answer HTTP 200? Or a full round trip - library scan finds a seeded file and a
  client streams it? The last one is the only assertion that would have caught a
  bind-mount permissions bug.
- **Where does it live?** A shell script in the repo, a CI job, or a documented
  manual runbook. There is no CI configured and no remote yet, which bears on
  this.

Answering this fixes the destination's acceptance criterion, so it should be
settled before the repo accumulates much that would need retrofitting.

## Resolution

**The acceptance criterion for the destination is now: `scripts/verify-portability.sh`
exits 0 on a GitHub Actions `ubuntu-24.04` runner.**

Decisions:

- **Clean host: GitHub Actions `ubuntu-24.04`** (remote:
  `https://github.com/grez-lucas/media-server`). Genuinely pristine per run, no
  local state drift. Local VM tooling was rejected - none is installed on this
  host anyway, and a second runner would have meant maintaining two copies of the
  assertions.
- **Docker is a prerequisite, asserted and never installed.** The script fails
  loudly with the install URL if it or the Compose plugin is missing. Bootstrapping
  container runtimes is not this repo's job, and the CI image ships both.
- **Full round trip, with a self-generated fixture.** The script synthesises a
  five-second 640x480 H.264 clip via the Jellyfin container's bundled ffmpeg
  (7.1.4), writes it into `MEDIA_ROOT`, completes Jellyfin's startup wizard over
  the API, adds a Movies library at `/data/movies`, waits for the scan, and asserts
  bytes come back from `/Videos/{id}/stream`. Deterministic, ~160KB, no licensing
  question, identical on CI where no library exists.
- **One script, thin callers.** `scripts/verify-portability.sh` runs locally and
  from `.github/workflows/portability.yml`. It uses its own compose project name,
  a `mktemp` workspace and ports 18096/17878/18989, so it never touches a live
  stack.

### Verified green

```
==> Prerequisites (asserted, never installed)
  PASS docker present: Docker version 29.7.1, build e9452d6
  PASS compose plugin present: 5.4.0
  PASS docker daemon reachable
==> Scratch workspace
  PASS built .env from .env.example with MEDIA_ROOT=/tmp/media-server-verify-tpW9cL/media
  PASS compose.yaml parses with every variable resolved
==> docker compose up -d
  PASS stack started
  PASS jellyfin ready after ~10s
  PASS radarr ready after ~2s
  PASS sonarr ready after ~2s
==> Library path identity across services
  PASS all three services see the library at /data with movies+tv
==> Media fixture
  PASS fixture written and visible on the host (160K)
==> Jellyfin round trip
  PASS startup wizard completed
  PASS authenticated as verify
  PASS Movies library added at /data/movies
  PASS fixture indexed by Jellyfin (item 2d36beb11b8565b12396fc6307669f45) after ~4s
  PASS streamed 65536 bytes back from the library
PORTABILITY VERIFIED   (exit 0)
```

### Verified green on the clean host - the destination's claim now holds

Run https://github.com/grez-lucas/media-server/actions/runs/31533312916, exit 0.

```
Ubuntu 24.04.4 LTS
Docker version 28.0.4, build b8034c0
Docker Compose version v2.38.2

  PASS docker daemon reachable
  PASS compose.yaml parses with every variable resolved
  PASS stack started
  PASS jellyfin ready after ~16s
  PASS radarr ready after ~2s
  PASS sonarr ready after ~2s
  PASS all three services see the library at /data with movies+tv
  PASS fixture written and visible on the host (152K)
  PASS startup wizard completed
  PASS authenticated as verify
  PASS Movies library added at /data/movies
  PASS fixture indexed by Jellyfin (item 2d36beb11b8565b12396fc6307669f45) after ~2s
  PASS streamed 65536 bytes back from the library
PORTABILITY VERIFIED
```

Worth noting the runner ships **Docker 28.0.4 / Compose v2.38.2** against this
host's **29.7.1 / 5.4.0**. The pass therefore also demonstrates the stack does not
depend on the local Docker version, which a same-version rerun could not have
shown. It does *not* yet say anything about image drift - that is 008.

### Defects the test found in ticket 001's work

Writing the test was worth it before it ever ran on CI - it found three real
problems in the compose file and in how 001 verified itself.

1. **`container_name` was hardcoded**, which defeats Compose's project
   namespacing. No second instance could ever coexist - not the harness, not a
   staging stack, not two copies on one host. Removed; Compose now names
   containers `media-server-<service>-1`. Consequence: `docker exec jellyfin ...`
   no longer works, use `docker compose exec jellyfin ...`.
2. **Host ports were fixed**, so any host already using 8096 could not run the
   stack at all. Now injected as `JELLYFIN_PORT` / `RADARR_PORT` / `SONARR_PORT`
   with the old values as defaults.
3. **Ticket 001 verified liveness and called it readiness.** Jellyfin serves
   HTTP 200 on `/` (static web UI) while the server is still starting and every
   API call answers `503 "Jellyfin Server is loading"`. 001's HTTP 200 evidence
   was true but weaker than it looked. The harness now probes
   `/System/Info/Public` for `"Version"` and the `*arr` `/ping` for `"OK"`.

### Jellyfin startup API facts later tickets depend on

Both cost real debugging time and are not obvious from the OpenAPI spec:

- **Do not send `X-Emby-Authorization` to `/Startup/*`.** Those endpoints sit
  behind the `FirstTimeSetupOrElevated` policy; supplying the header makes
  Jellyfin treat the call as authenticated, the policy fails, and it answers
  **404** rather than 403.
- **`GET /Startup/User` must precede `POST /Startup/User`.** The GET materialises
  the default user record that the POST renames. Without it the POST has nothing
  to update and returns **404**.
- Working order: `POST /Startup/Configuration` -> `GET /Startup/User` ->
  `POST /Startup/User` -> `POST /Startup/Complete` ->
  `POST /Users/AuthenticateByName` (this one *does* need the auth header) ->
  `POST /Library/VirtualFolders`.

### Bearing on other tickets

- **Unblocks 008 and it now matters.** The test asserts a real streaming round
  trip, so floating `latest` tags will make it flap. Pinning stopped being
  optional the moment this decision landed.
- **Unblocks 005.** "Compose only" is now a testable position rather than an
  assumption: the harness proves a clean host reaches a working stack with no
  committed config at all.
- **Jellyfin version under test is 10.11.11.** The startup API quirks above are
  version-specific, which is another argument for 008.
