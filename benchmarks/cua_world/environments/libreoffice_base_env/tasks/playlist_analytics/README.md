# playlist_analytics

## Overview

**Domain**: Digital content management / music platform curation
**Occupation context**: Content curators and music catalog managers at digital streaming platforms need to analyze playlist compositions, track artist exposure, and tag playlists for curation workflows.

The Chinook database contains 18 real playlists (e.g., "Music", "Movies", "TV Shows", "Classical", "Grunge") spanning 3503 tracks across 275 artists. A content curator must build analytical views and a tagging system.

## Goal

The end state must include all of the following in the `chinook.odb` LibreOffice Base file:

1. **A saved query named `PlaylistSummary`** — joins `Playlist`, `PlaylistTrack`, and `Track` tables, GROUP BY playlist, and computes: `PlaylistId`, `Name`, `TrackCount` (number of tracks), `TotalMilliseconds` (SUM of track durations), `TotalRevenue` (SUM of track UnitPrices).

2. **A saved query named `TopArtistsInPlaylists`** — joins `Artist`, `Album`, `Track`, `PlaylistTrack`, and optionally `Playlist` to compute how many distinct playlists each artist appears in; must GROUP BY artist and ORDER BY playlist count descending.

3. **A table named `PlaylistTag`** with at least columns: `TagId` (integer, primary key), `PlaylistId` (integer), `TagName` (text), `AddedDate` (date).

4. **At least 5 rows in `PlaylistTag`** — using real Chinook playlist IDs (1–18). Use a mix of realistic tags (e.g., "workout", "focus", "classic rock", "study") across multiple playlist IDs.

5. **A form named `Playlist Tagger`** (name must contain "Playlist") — a data-entry form for adding tags to playlists.

## Verification Strategy

| Criterion | Points | Method |
|-----------|--------|--------|
| `PlaylistSummary` query with correct joins | 25 | Parse content.xml, check JOIN + GROUP BY + Track refs |
| `TopArtistsInPlaylists` query with 4-5 table joins | 25 | Parse content.xml, check Artist + PlaylistTrack + GROUP BY |
| `PlaylistTag` table created | 20 | Parse database/script for CREATE TABLE |
| PlaylistTag has 5+ rows | 15 | Count INSERTs in database/script |
| Form containing "Playlist" created | 15 | Parse content.xml/ZIP for forms |
| **Total** | **100** | Pass threshold: 70 |

## Schema Reference

Relevant Chinook tables:
- `Playlist` (PlaylistId INTEGER PK, Name VARCHAR)
  - Real playlists: Music (1), Movies (2), TV Shows (3), Audiobooks (4), 90's Music (5), Podcasts (6), Grunge (7), Movies (8), Music Videos (9), Classical (14), Classical 101 - Deep Cuts (16), Heavy Metal Classic (17), ...
- `PlaylistTrack` (PlaylistId, TrackId) — junction table, ~8271 rows
- `Track` (TrackId, Name, AlbumId, MediaTypeId, GenreId, Composer, **Milliseconds**, Bytes, **UnitPrice**)
- `Album` (AlbumId, Title, **ArtistId**)
- `Artist` (ArtistId INTEGER PK, Name VARCHAR)

Example PlaylistSummary query:
```sql
SELECT p."PlaylistId", p."Name",
       COUNT(pt."TrackId") AS TrackCount,
       SUM(t."Milliseconds") AS TotalMilliseconds,
       SUM(t."UnitPrice") AS TotalRevenue
FROM "Playlist" p
JOIN "PlaylistTrack" pt ON p."PlaylistId" = pt."PlaylistId"
JOIN "Track" t ON pt."TrackId" = t."TrackId"
GROUP BY p."PlaylistId", p."Name"
ORDER BY TrackCount DESC
```

## Credentials

- **Login**: Username `ga`, password `password123`
- **Application**: LibreOffice Base with `/home/ga/chinook.odb`
