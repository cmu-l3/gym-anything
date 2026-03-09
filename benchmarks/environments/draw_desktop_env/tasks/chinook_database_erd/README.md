# chinook_database_erd — Physical ERD from Chinook Database Schema

## Domain Context

**Occupation**: Computer Systems Analyst (top GDP occupation for diagramming tools, $2.5B)

Database developers and systems analysts routinely create Physical Entity-Relationship Diagrams (ERDs) as part of database migration and documentation projects. Physical ERDs differ from logical ERDs in that they show actual column names, data types, primary keys, foreign keys, and cardinality — the exact information needed by DBAs and developers working with a real schema.

The Chinook database is a real-world sample database (originally by Luis Rocha, Microsoft sample format) representing a digital media store. It is widely used in database education and tooling because it has a rich relational schema with 11 tables spanning multiple business domains.

## Task Description

A Database Developer at a music streaming startup must create a complete Physical ERD for the Chinook database before migrating to a new cloud data warehouse. The SQL schema file (`chinook_schema.sql`) is provided on the Desktop.

**End state**: A multi-page draw.io diagram file (`~/Desktop/chinook_erd.drawio`) and a PNG export (`~/Desktop/chinook_erd.png`) that contain:
- Entity boxes for all 11 Chinook tables: Artist, Album, Track, MediaType, Genre, Playlist, PlaylistTrack, Invoice, InvoiceLine, Customer, Employee
- Each entity box shows columns with PK/FK indicators
- Relationship lines between tables with FK relationships, using crow's foot cardinality notation
- Logical subject-area groups (≥3): e.g., Media Catalog (Artist/Album/Track/Genre/MediaType), Commerce (Invoice/InvoiceLine/Customer), Organization (Employee/Playlist/PlaylistTrack)
- A second diagram page titled "Relationship Summary" listing FK relationships as text

## Why This Is Hard

- The agent must read and parse a real SQL DDL file with 11 CREATE TABLE statements and understand FK constraints
- Mapping FK references to crow's foot cardinality (one-to-many vs many-to-many) requires schema understanding
- Organizing 11 entities into logical groups requires domain judgment (not just mechanical placement)
- Draw.io has no dedicated "import SQL as ERD" function — the agent must build the diagram manually
- The task requires using multiple draw.io features: entity shape types, crow's foot connectors, page management, group shapes, PNG export

## Success Criteria

| Criterion | Points | Threshold |
|-----------|--------|-----------|
| File saved after task start | 10 | Required (early exit if missing) |
| ≥9 of 11 tables as shapes | 25 | Partial: 5+ tables = 10 pts |
| ≥7 FK relationship edges | 20 | Partial: 3+ edges = 8 pts |
| ≥2 diagram pages | 15 | — |
| PK/FK keywords in shapes | 10 | Partial: ≥2 keywords = 5 pts |
| Logical domain groups | 10 | — |
| PNG exported (≥2000 bytes) | 10 | Partial: any PNG = 5 pts |
| **Total** | **100** | **Pass: ≥60** |

## Verification Strategy

The verifier (`verify_chinook_database_erd`):
1. Reads `/tmp/task_result.json` exported by `export_result.sh`
2. Checks file existence and modification timestamp (must be after task start)
3. Counts entity shapes by scanning vertex shape labels for table name matches (case-insensitive)
4. Counts edges from the draw.io XML (`edge="1"` attributes)
5. Detects PK/FK keywords from shape text content
6. Detects group/swimlane containers
7. Checks PNG file existence and size via filesystem stats

## Data Source

The Chinook DDL in `setup_task.sh` is transcribed from the real Chinook database schema (v1.4, MIT license). The schema is documented at https://github.com/lerocha/chinook-database.

**Key relationships to capture**:
- Artist (1) → Album (many) via `AlbumId`
- Album (1) → Track (many) via `AlbumId`
- MediaType (1) → Track (many) via `MediaTypeId`
- Genre (1) → Track (many) via `GenreId`
- Customer (1) → Invoice (many) via `CustomerId`
- Invoice (1) → InvoiceLine (many) via `InvoiceId`
- Track (1) → InvoiceLine (many) via `TrackId`
- Playlist (many) ↔ Track (many) via `PlaylistTrack`
- Employee (1) → Customer (many) via `SupportRepId`
- Employee (1) → Employee (many) via `ReportsTo` (self-referential)

## Files

| File | Purpose |
|------|---------|
| `task.json` | Task specification, metadata, scoring hook |
| `setup_task.sh` | Creates `~/Desktop/chinook_schema.sql`, records start timestamp, launches draw.io |
| `export_result.sh` | Parses draw.io XML (handles compressed + uncompressed), extracts shape/edge counts, checks PNG |
| `verifier.py` | Multi-criterion scoring function `verify_chinook_database_erd` |

## Edge Cases

- draw.io may save files in compressed format (base64 + raw-deflate); `export_result.sh` handles both
- Table names may appear with alternate capitalizations or abbreviations — verifier uses case-insensitive matching and partial aliases (e.g., "invoiceline" matches "InvoiceLine")
- Crow's foot connectors have specific style strings; verifier does not require specific connector styles, only counts edges
- An agent might draw all 11 tables but miss the second page — this correctly gives partial credit (no page bonus)
