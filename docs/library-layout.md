# Library layout

Decided in WF-003. Radarr and Sonarr are **authoritative** for naming: renaming
is on, they impose this convention on import and on any later change, and nothing
else writes to the library tree.

This file is the committed record. The live settings sit in `config/`, which is
gitignored, so **this document is the source of truth and the running config is a
copy of it**. Whether that copy should be seeded automatically is WF-005.

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

## Changing any of this

Cheap now, expensive later. These templates rewrite the library on the next
rename, and Jellyfin has watch state keyed to the items involved. Treat a change
here as a migration, not an edit.
