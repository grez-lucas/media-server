# media-server

A LAN-only media stack - [Jellyfin](https://jellyfin.org), [Radarr](https://radarr.video)
and [Sonarr](https://sonarr.tv) - that reconstitutes itself on any clean Ubuntu
24.04 machine from this repo alone.

**Portable means config-portable.** The repo rebuilds the stack anywhere; the
library stays behind. `MEDIA_ROOT` is the single seam between the two.

## Three steps

```bash
git clone https://github.com/grez-lucas/media-server && cd media-server
cp .env.example .env && $EDITOR .env      # set MEDIA_ROOT, PUID/PGID, TZ, secrets
docker compose up -d
scripts/seed.sh
```

That is the whole contract, and it is the contract CI tests: every push runs
`scripts/verify-portability.sh` on a fresh `ubuntu-24.04` runner, which does
exactly the above and then asserts a full round trip - synthesise a media file,
make Jellyfin index it, stream the bytes back.

It is three steps rather than one on purpose. The seed **refuses** to overwrite a
host that already disagrees with the repo, and exits non-zero to say so. That is
a useful signal at a prompt and a recurring mystery inside a compose init
container, so it stays a command you run.

### Prerequisites, asserted and never installed

Docker with the Compose v2 plugin, and Python 3.8+. Both scripts check for them
and fail with a message rather than reaching for your package manager.

## What each step does

| step | result |
|---|---|
| `docker compose up -d` | three services, config in `./config`, library at `${MEDIA_ROOT}` mounted to `/data` in all of them |
| `scripts/seed.sh` | root folders, naming templates and Jellyfin libraries applied from `seed/conventions.json` |

Everything host-specific is injected through `.env`, which is gitignored and is
the only file that should differ between machines. Secrets included: the seed
knows every credential before the first container starts and never reads anything
out of `./config`.

## Running it again

`scripts/seed.sh` is idempotent. On a host that already matches it reports
`ALREADY SEEDED` and writes nothing; on one that has drifted it prints each
difference and exits 1 without touching anything.

```
scripts/seed.sh            # converge a blank host, or report drift on a configured one
scripts/seed.sh --force    # actually converge a configured host
```

Because one code path does both, **the seeder is also the drift checker** - there
is no second tool to keep in step.

## Layout

```
compose.yaml                 the stack. Images pinned <version>@sha256:<digest>
seed/conventions.json        the VALUES the conventions consist of
docs/library-layout.md       the REASONING behind those values
scripts/seed.sh              applies them, or refuses and explains
scripts/verify-portability.sh  the clean-host round trip CI runs
.env.example                 every host-specific value, documented
```

## What this is not

- **Not internet-exposed.** LAN only. No reverse proxy, no TLS, no auth
  hardening. That is a separate effort.
- **Not a backup.** The repo carries conventions, not state - accounts, watch
  progress and the `*arr` monitored lists are currently protected by nothing.
  Tracked in [#18](https://github.com/grez-lucas/media-server/issues/18).
- **Not hardware-accelerated.** The base compose is deliberately
  hardware-agnostic. Transcoding gets built when a named trigger fires, as a
  gitignored per-host override - see
  [#9](https://github.com/grez-lucas/media-server/issues/9).
- **Not a downloader.** Radarr and Sonarr ship as library organisers with no
  indexer and no download client configured.

## Planning

Design decisions are worked as a map of issues on this repo's tracker - see the
[map](https://github.com/grez-lucas/media-server/issues/2) for what is settled
and what is still open, and `.wayfinder/TRACKER.md` for the conventions.
