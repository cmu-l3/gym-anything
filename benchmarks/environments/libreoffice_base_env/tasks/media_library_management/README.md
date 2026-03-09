# media_library_management

## Overview

**Domain**: Digital media librarianship / catalog management
**Occupation context**: Library Technicians and Digital Media Librarians at institutions maintain track catalogs for digital asset management systems. The Chinook database represents a digital media store's track catalog; a librarian must build comprehensive catalog views and add metadata annotations.

## Goal

The end state must include all of the following in the `chinook.odb` LibreOffice Base file:

1. **A saved query named `FullTrackCatalog`** — a 5-table join across `Track`, `Album`, `Artist`, `Genre`, and `MediaType` tables. Must produce columns: TrackId, TrackName (or track Name), AlbumTitle, ArtistName, GenreName, MediaTypeName, Milliseconds, UnitPrice.

2. **A saved query named `GenreMediaBreakdown`** — joins `Genre`, `Track`, and `MediaType` tables, GROUP BY genre AND media type, computing TrackCount and total revenue (SUM of UnitPrice). Shows the intersection of genre and media format.

3. **A table named `TrackReview`** with at least columns: `ReviewId` (integer, primary key), `TrackId` (integer), `Rating` (integer, 1–5 scale), `ReviewText` (text/LONGVARCHAR), `ReviewDate` (date).

4. **At least 5 rows in `TrackReview`** — using real Chinook track IDs (valid range: TrackId 1–3503). Use diverse track IDs and ratings between 1 and 5.

5. **A report named `Media Catalog`** (name must contain "Catalog" or "Media") — presenting the track catalog data.

## Verification Strategy

| Criterion | Points | Method |
|-----------|--------|--------|
| `FullTrackCatalog` query with 5-table joins | 25 | Parse content.xml, check Track+Album+Artist+Genre+MediaType refs |
| `GenreMediaBreakdown` query with GROUP BY + aggregate | 20 | Parse content.xml, check Genre + MediaType + GROUP BY |
| `TrackReview` table created | 20 | Parse database/script for CREATE TABLE |
| TrackReview has 5+ rows with valid ratings 1–5 | 20 | Count INSERTs + check rating values |
| Report containing "Catalog" or "Media" created | 15 | Parse content.xml/ZIP for reports |
| **Total** | **100** | Pass threshold: 70 |

## Schema Reference

Relevant Chinook tables:
- `Track` (TrackId, **Name**, **AlbumId**, **MediaTypeId**, **GenreId**, Composer, **Milliseconds**, Bytes, **UnitPrice**)
- `Album` (AlbumId, **Title**, **ArtistId**)
- `Artist` (ArtistId, **Name**)
- `Genre` (GenreId, **Name**)
- `MediaType` (MediaTypeId, **Name**)
  - Media types: MPEG audio file, Protected AAC audio file, Protected MPEG-4 video file, Purchased AAC audio file, AAC audio file

Example FullTrackCatalog query:
```sql
SELECT t."TrackId", t."Name" AS TrackName, al."Title" AS AlbumTitle,
       ar."Name" AS ArtistName, g."Name" AS GenreName,
       mt."Name" AS MediaTypeName,
       t."Milliseconds", t."UnitPrice"
FROM "Track" t
JOIN "Album" al ON t."AlbumId" = al."AlbumId"
JOIN "Artist" ar ON al."ArtistId" = ar."ArtistId"
JOIN "Genre" g ON t."GenreId" = g."GenreId"
JOIN "MediaType" mt ON t."MediaTypeId" = mt."MediaTypeId"
ORDER BY ar."Name", al."Title", t."Name"
```

Valid Chinook Track IDs: 1–3503 (real tracks include AC/DC tracks starting at TrackId 1)
- TrackId 1: "For Those About To Rock (We Salute You)" by AC/DC, Rock, MPEG audio file
- TrackId 2: "Balls to the Wall" by Accept, Rock, Protected AAC audio file
- TrackId 3: "Fast As a Shark" by Accept, Rock, Protected AAC audio file

## Credentials

- **Login**: Username `ga`, password `password123`
- **Application**: LibreOffice Base with `/home/ga/chinook.odb`
