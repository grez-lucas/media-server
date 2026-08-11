---
id: 008
title: Decide the image pinning strategy
labels: [wayfinder:grilling]
state: closed
assignee: luken
blocked_by: [004]
---

## Question

Graduated from the map's fog by ticket 001, which made the problem concrete
rather than theoretical. The committed `compose.yaml` requests `:latest` for all
three services. At build time that resolved to:

```
jellyfin  32cc24a646a4  (built 6 hours before the pull)
radarr    5a29acd9cee5  (9 days)
sonarr    de227c8e8683  (3 days)
```

Nothing in the repo records those. A clean host cloning this repo next month gets
different software, which sits badly against a destination whose whole claim is
"works on any clean Ubuntu machine". Right now the repo is portable in space but
not in time.

What is the strategy?

- **Track `latest`.** Simplest, always current, and security patches arrive
  without action. Reproducibility is nil, and a breaking upstream change lands
  silently on the next `pull`.
- **Pin major/minor tags** (`jellyfin:10.10`). Middle ground - upstream still
  ships patches within the tag, and the blast radius of a surprise is smaller.
- **Pin digests** (`image@sha256:...`). Genuinely reproducible, and the only
  option under which ticket 004's portability test proves anything durable. Cost
  is a deliberate update ritual, since nothing moves until a human changes a
  hash.
- **Automated updates** (Watchtower or similar) as an orthogonal add-on. Worth
  deciding explicitly rather than by omission, because it is the opposite of
  pinning and the two are easy to end up with simultaneously.

Bearing on the decision:

- Blocked by 004 because "what does portable prove" determines whether
  reproducibility is part of the acceptance criterion or not. If the test only
  asserts three containers reach `running`, `latest` is fine. If it asserts a
  known-good round trip, floating tags will make it flap.
- The `*arr` apps hold SQLite databases with schema migrations that do not go
  backwards. An accidental major upgrade is not always reversible by pinning back
  to the old tag, which raises the stakes above ordinary version drift.
- This interacts with ticket 005: whatever travels with the repo to reconstitute
  a host is only meaningful against a known software version.

## Resolution

**Pin `<version>@sha256:<digest>`, update via Renovate PRs, gate merges on the
portability check.** The two goals were not traded off against each other: the
digest gives reproducibility, Renovate keeps it current including base-OS
security rebuilds, and CI proves each bump before it lands.

### The fact that decided it

A bare version tag would **not** have been reproducible. LinuxServer rebuilds
tags in place as `ls43 -> ls44` for base-OS patches, and jellyfin's `latest` has
already carried its base image across `ubu2404 -> ubu2604`. Only a digest is
immutable.

The mirror of that: **digest pinning alone freezes out those same security
rebuilds**, because they arrive as a new digest under an unchanged version tag.
Pinning without an update channel is strictly worse than `latest` for security -
which is why WF-009 exists and why this decision is not finished until it closes.

### Pinned to

Verified: all three semver tags resolve to exactly the digests CI proved green in
run 31533312916, so the pins lock known-good images rather than whatever was
newest.

| service | tag | digest | app version |
|---|---|---|---|
| jellyfin | `10.11.11` | `sha256:0dd18f8de37c…` | 10.11.11 |
| radarr | `6.3.0` | `sha256:a45b5ab0f850…` | 6.3.0.10514-ls313 |
| sonarr | `4.0.19` | `sha256:373159ba768e…` | 4.0.19.2979-ls321 |

The tag is carried alongside the digest purely so a human can read the version in
a diff. Docker enforces the digest.

### renovate.json

- `config:recommended` + `docker:pinDigests`.
- **One PR per service**, never grouped, so a bad upgrade is isolated and the
  portability check can attribute the failure.
- **Major bumps require dependency-dashboard approval.** Radarr and Sonarr run
  forward-only SQLite schema migrations; once the database has moved, pinning
  back to the previous digest does not undo it. This is the one upgrade class
  that is not cheaply reversible.
- **Digest-only updates flow freely** - those are the security rebuilds.
- **Automerge left `false`** deliberately. It is a separate decision and was not
  implied by this one.

### Verified

- `scripts/verify-portability.sh` exits 0 locally against the pinned digests.
- CI green on the pinned commit: run 31533869813 (`dfe3908`).

### Not done here

Branch protection was attempted and **denied by the agent's permission
classifier**, so `main` is currently unprotected and the gate decided in Q3 is
not yet enforced. Renovate is also not installed. Both moved to WF-009 with the
exact command and check-run name (`Clean-host round trip`).
