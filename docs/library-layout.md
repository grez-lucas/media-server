# Library layout

Decided in WF-003. Radarr and Sonarr are **authoritative** for naming: renaming
is on, they impose this convention on import and on any later change, and nothing
else writes to the library tree.

## What this document is, and is not

**This document owns the reasoning. `seed/conventions.json` owns the values.**

That split landed with the seed in
[#17](https://github.com/grez-lucas/media-server/issues/17). Before it, this file
claimed to be the source of truth for both, and the live settings sat only in the
gitignored `config/` tree where nothing could check them.

| | owns | checked by |
|---|---|---|
| this document | why each value is what it is | a human reading it |
| `seed/conventions.json` | the values themselves | `scripts/seed.sh` on every CI push |

So a value appears in **exactly one** place. When they disagree the data file is
what runs, which is precisely why every value in it has to trace back to a
paragraph here - `seed/conventions.json` was **authored from this document**,
never extracted from a host. Extracting would canonise settings nobody
deliberated.

**Changing a convention means changing both**, in this order: argue it here,
then change the value there. `scripts/seed.sh` refuses to overwrite a configured
host precisely so that the change stays a deliberate act - see *Changing any of
this* at the end.

## Roots

| root | container path | host path |
|---|---|---|
| Movies | `/data/movies` | `${MEDIA_ROOT}/movies` |
| TV | `/data/tv` | `${MEDIA_ROOT}/tv` |

All three services mount `${MEDIA_ROOT}` at `/data`, identically. Radarr's and
Sonarr's root folders use the **container** path. Pointing Jellyfin at
`/srv/media/movies` instead of `/data/movies` yields a silently empty library.

## Movies (Radarr)

```
renameMovies       true
movieFolderFormat  {Movie Title} ({Release Year}) [imdbid-{ImdbId}]
standardMovieFormat {Movie Title} ({Release Year}) [imdbid-{ImdbId}] - {Quality Full}
```

Renders as:

```
Movies/
  The Movie - Title (2010) [imdbid-tt0066921]/
    The Movie - Title (2010) [imdbid-tt0066921] - Bluray-1080p Proper.mkv
```

## Shows (Sonarr)

```
renameEpisodes       true
seriesFolderFormat   {Series Title} ({Series Year}) [tvdbid-{TvdbId}]
seasonFolderFormat   Season {season:00}
standardEpisodeFormat {Series Title} - S{season:00}E{episode:00} - {Episode Title} {Quality Full}
```

Renders as:

```
TV/
  The Series Title's! (2010) [tvdbid-12345]/
    Season 01/
      The Series Title's! - S01E01 - Episode Title (1) WEBDL-1080p Proper.mkv
```

## Why these differ from the *arr defaults

Three of the shipped defaults are wrong for Jellyfin. Each was measured against
Jellyfin 10.11.11 rather than taken from documentation.

### 1. The version separator must be ` - `, not a space

Radarr's default `standardMovieFormat` separates the quality label with a bare
space. Measured, with two quality variants in one folder:

| filenames | Jellyfin result |
|---|---|
| `Title (1997) - 480p` + `Title (1997) - 720p` | **1 item, 2 media sources** |
| `Title (1996) 480p` + `Title (1996) 720p` | **2 items - the same film listed twice** |

So the separator is not cosmetic and it is not about title parsing: Jellyfin
strips known quality tokens either way, and both shapes give the correct title
and year. What the bare space breaks is the *multiple versions* feature, and the
symptom is a duplicated library entry once a film exists in more than one
quality.

`scripts/verify-portability.sh` asserts this with a two-file fixture. A one-file
fixture passes under both conventions and proves nothing.

### 2. Sonarr's series folder has no year

The default `seriesFolderFormat` is `{Series Title}` alone. Jellyfin's docs call
the year and provider id out as what makes matching reliable, and without a year
`The Office` has to be disambiguated against several unrelated shows.

### 3. Sonarr's season folder is not zero-padded

The default renders `Season 1`. Jellyfin accepts it but documents `Season 01` as
preferred, and unpadded folders sort wrongly past nine seasons.

## Provider ids

`[imdbid-...]` and `[tvdbid-...]` are optional per Jellyfin's docs but remove
fuzzy title matching entirely. Radarr and Sonarr populate them natively.

The portability check deliberately does **not** use them in its fixture: a fake
id would exercise Jellyfin's remote metadata lookup and make CI depend on a third
party. It asserts the parsing this repo controls.

## Extra files on import (Radarr)

```
importExtraFiles     true
extraFileExtensions  srt
```

`importExtraFiles` shipped **off**, which silently dropped any subtitle that came
alongside an imported release: the video moved into the library and the `.srt`
was left behind in the source folder. `extraFileExtensions` was already `srt`, so
the extension list was never the thing holding it back. Turned on 2026-08-12
while importing a release that carried its own subtitle.

With it on, Radarr renames the sidecar onto the video's basename and carries any
language suffix through untouched, measured against Radarr 6.3.0:

```
Logan.2017.1080p.BluRay.x264.VPPV.en.srt
  -> Logan (2017) [imdbid-tt3315342] - Bluray-1080p.en.srt
```

Radarr records the result in its `ExtraFiles` table keyed by **relative path**,
and renames tracked sidecars alongside the video on any later rename or quality
upgrade. Two consequences worth knowing before touching a subtitle by hand:

- Renaming a sidecar on disk behind Radarr strands that record: the stored path
  stops matching the file. The orphaning that follows at the next rename is
  **inferred from the record structure, not measured** - forcing a rename to
  observe it would rewrite the library, which this document treats as a
  migration. Restage and reimport instead, or `RescanMovie` to rebuild the
  record.
- The language suffix rides along as part of the basename. `languageTags` on the
  record stays `[]` - Radarr did not parse `.en` into a structured tag, so it
  would not re-derive the suffix if a filename ever lost it.

**Extra-file matching is per source folder, not per release.** Importing two
releases from one flat staging folder attached the first film's `.srt` to the
second film's video: Radarr scans the imported file's directory for sidecars and
does not check that the basenames correspond. Observed on a two-film manual
import, and the reason a manual import stages one release per folder.

## The sidecar naming convention is not settled here

This section records a Radarr **import behaviour** and the drift it fixes. It
does **not** record the sidecar naming convention, which
[#13](https://github.com/grez-lucas/media-server/issues/13) deliberately deferred:
that convention depends on the WebOS subtitle measurement in
[#14](https://github.com/grez-lucas/media-server/issues/14) and lands with the
Bazarr build in [#15](https://github.com/grez-lucas/media-server/issues/15).

So the `.en.srt` above is what Radarr currently emits, not a ratified shape. Two
divergences stand open until #15 closes them:

- The tree already carries two sidecar shapes - `.en.srt` from a Radarr import and
  `Carrie (1976) - 1080p.es.srt` placed by hand. Neither is authoritative yet.
- #13 makes Bazarr the writer of fetched subtitles. Radarr importing a subtitle
  that shipped inside a release is a different path and does not conflict with
  that, but which of the two owns a sidecar when both could supply one is
  #15 territory.

## Extra files on import (Sonarr)

The same setting, the same reasoning, applied to television. Sonarr shipped
`importExtraFiles` **off** and this host still had it off when
[#17](https://github.com/grez-lucas/media-server/issues/17) seeded it - so a TV
release arriving with its own `.srt` would have dropped it on import exactly as a
movie release did, and nobody had noticed because no TV had been imported yet.

Recorded here rather than silently copied into the data file: authoring the data
file *from this document* is what generalises the Radarr paragraph above to
Sonarr. The document observed it on Radarr only because that is where it was
first hit, not because it was ever a movies-only concern.

## What the seed does NOT carry

`seed/conventions.json` holds conventions - Tier 1 in
[#7](https://github.com/grez-lucas/media-server/issues/7)'s terms. It deliberately
does not hold:

- **Accounts and per-user preferences** (Tier 2), or **watch progress and the
  `*arr` monitored lists** (Tier 3). Those are
  [#18](https://github.com/grez-lucas/media-server/issues/18)'s, and until it
  lands they are protected by nothing.
- **Jellyfin's `TypeOptions`.** A library created through the API writes an empty
  `<TypeOptions />` where one created in the UI carries a populated block, and #7
  left open whether empty meant "fetch nothing". Measured on Jellyfin 10.11.11 -
  two libraries in one server, one fixture, created respectively with `{}` and
  with a full payload - both returned identical `ProviderIds`, rating, genres,
  images and overview. **Empty falls back to defaults at runtime.** There is
  nothing to pin, and pinning it would make the seed report a difference against
  every library a human made in the UI.
- **Secrets.** They are injected from `.env`, never discovered - see
  `.env.example`.

## Changing any of this

Cheap now, expensive later. These templates rewrite the library on the next
rename, and Jellyfin has watch state keyed to the items involved. Treat a change
here as a migration, not an edit.

`scripts/seed.sh` enforces that. On a host that is already configured it
**compares, reports every difference, and writes nothing**, exiting non-zero;
`--force` is the deliberate act that converges. One code path, so the seeder is
also the drift checker, which is what CI calls to assert a running stack still
matches the file.
