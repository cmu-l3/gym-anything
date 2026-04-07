# Task: PostgreSQL 13 → 15 Database Migration

## Domain Context

Database administrators and DevOps engineers regularly perform major-version PostgreSQL migrations. These migrations require `pg_dump`/`pg_restore` (or `pg_upgrade`) to transfer schema and data between incompatible binary formats, then verification that all data arrived intact. A failed migration can result in data loss, broken foreign keys, or silent corruption.

## Environment State

A PostgreSQL 13 container named `chinook-pg13` is running on port **5433** with:
- Database: `chinook`
- Username: `chinook`
- Password: `chinook_secret_2019`

The database contains the Chinook music store dataset: Artists, Albums, Tracks, Customers, Employees, Invoices, Playlists, and related junction tables (11 tables total with hundreds of rows).

## Goal

The end state should have:
1. A **running PostgreSQL 15 container** named `chinook-pg15`, accessible on port **5434**
2. The **complete Chinook database** migrated into it (database name: `chinook`, same credentials)
3. **All 11 tables present** with row counts matching the source
4. The data must be **queryable** — a JOIN-based query across tables must succeed

The source container `chinook-pg13` may remain running (do not destroy evidence).

## Success Criteria

| Criterion | Points |
|-----------|--------|
| chinook-pg15 container is running | 20 |
| chinook database exists in PG15 and is reachable | 15 |
| Artist + Employee + Customer row counts match PG13 | 30 (10 each) |
| All 11 expected tables present in PG15 | 20 |
| Container created after task start (not pre-existing) | 15 |
| **Total** | **100** |
| **Pass threshold** | **65** |

## Verification Strategy

The verifier:
1. Checks `docker inspect chinook-pg15` for running state and creation time
2. Uses `docker exec chinook-pg15 psql -U chinook -d chinook` to verify connectivity
3. Compares row counts in PG15 against baseline counts recorded from PG13 at task start
4. Checks `information_schema.tables` for all 11 expected table names
5. Applies score cap if data counts don't match (migration was incomplete or corrupted)

## Schema Reference

Key tables (11 total):
- `Artist` (ArtistId, Name)
- `Album` (AlbumId, Title, ArtistId)
- `Track` (TrackId, Name, AlbumId, MediaTypeId, GenreId, ...)
- `Customer` (CustomerId, FirstName, LastName, Email, ...)
- `Employee` (EmployeeId, LastName, FirstName, Title, ...)
- `Invoice` / `InvoiceLine`
- `Playlist` / `PlaylistTrack`
- `MediaType`, `Genre`

## Notes

- Use `pg_dump` to dump from PG13 and `pg_restore` or `psql` to restore into PG15
- The `pg_dump` binary from PG15 image should be used for compatibility (dump with the newer client)
- Alternatively, `docker run --rm postgres:15 pg_dump ...` can dump from a remote source
- The PG15 container must use the same credentials as PG13 (database, username, password)
