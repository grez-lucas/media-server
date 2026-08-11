---
id: 008
title: Decide the image pinning strategy
labels: [wayfinder:grilling]
state: open
assignee: null
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
