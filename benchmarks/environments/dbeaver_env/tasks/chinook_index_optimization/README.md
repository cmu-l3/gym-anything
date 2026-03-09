# Task: Chinook Index Optimization

## Domain
Database Administration — Query Performance Tuning

## Occupation Context
**Database Administrators** (GDP impact: $1.0B, importance=96) use DBeaver as "the primary
interface for creating, configuring, querying, and managing database structures." **Database
Architects** (importance=94) use it for "query testing and database administration tasks."
This task reflects the real DBA workflow: a production database is slow, management escalates
three specific query complaints, and the DBA must analyze execution plans, design indexes, and
document the fix.

## Goal
Performance-tune the Chinook database by:
1. Analyzing EXPLAIN QUERY PLAN output for 3 slow queries
2. Creating targeted indexes to eliminate full table scans
3. Documenting the optimization in a formal performance report

## Database: Chinook (original)
- **Location**: `/home/ga/Documents/databases/chinook.db`
- **Connection name**: `Chinook`

## The Three Slow Queries

### Query A — Track Search by Duration & Price
```sql
SELECT t.Name, ar.Name as Artist, al.Title as Album, t.Milliseconds, t.UnitPrice
FROM tracks t
JOIN albums al ON t.AlbumId=al.AlbumId
JOIN artists ar ON al.ArtistId=ar.ArtistId
WHERE t.Milliseconds BETWEEN 180000 AND 420000 AND t.UnitPrice = 0.99
ORDER BY t.Milliseconds DESC;
```
**Bottleneck**: Full scan of `tracks` table (3503 rows) for Milliseconds and UnitPrice filter.
**Fix**: Index on `tracks(Milliseconds)` or `tracks(UnitPrice, Milliseconds)`.

### Query B — Revenue by Country and Date Range
```sql
SELECT i.InvoiceDate, c.Country, SUM(i.Total) as DailyTotal, COUNT(*) as OrderCount
FROM invoices i
JOIN customers c ON i.CustomerId=c.CustomerId
WHERE i.InvoiceDate >= '2011-01-01' AND i.InvoiceDate < '2013-01-01'
GROUP BY date(i.InvoiceDate), c.Country
ORDER BY DailyTotal DESC;
```
**Bottleneck**: Full scan of `invoices` (412 rows) for InvoiceDate range filter.
**Fix**: Index on `invoices(InvoiceDate)`.

### Query C — Genre Track Statistics
```sql
SELECT g.Name as Genre, COUNT(DISTINCT t.TrackId) as TrackCount,
       AVG(t.Milliseconds)/1000.0 as AvgDurationSec, AVG(t.UnitPrice) as AvgPrice
FROM tracks t
JOIN genres g ON t.GenreId=g.GenreId
WHERE t.Composer IS NOT NULL
GROUP BY g.GenreId
ORDER BY TrackCount DESC;
```
**Bottleneck**: Full scan of `tracks` for `Composer IS NOT NULL` filter.
**Fix**: Partial or full index on `tracks(Composer)` or `tracks(GenreId, Composer)`.

## Expected Deliverables

### 1. DBeaver Connection
- Name: `Chinook` (exact)

### 2. At Least 3 New Indexes
Agent must CREATE INDEX statements in DBeaver's SQL editor:
- At minimum one index on `tracks` (for Milliseconds/UnitPrice or Composer)
- At minimum one index on `invoices` (for InvoiceDate)
- Names should be descriptive (not generic like `idx1`)

### 3. Performance Report: `/home/ga/Documents/reports/index_report.txt`
Must document:
- Which indexes were created
- Which query each index optimizes
- Why the index helps (which column was causing the full scan)

## Verification Strategy

| Criterion | Points | Check |
|-----------|--------|-------|
| DBeaver 'Chinook' connection exists | 10 | data-sources.json |
| ≥3 new indexes created on correct tables | 30 | sqlite_master query |
| At least 1 index on tracks, 1 on invoices | 25 | table-level index check |
| index_report.txt exists at correct path | 20 | file existence + size |
| Report mentions all 3 queries or indexes | 15 | text search in report |

**Pass threshold: 60 points**

## Difficulty Factors
- Must understand EXPLAIN QUERY PLAN output to identify which scans are full table scans
- Must determine the correct column(s) to index for each query (not told the answer)
- Must name indexes descriptively (not generic) — tests understanding, not just execution
- Must produce a text report connecting each index to the query it optimizes
- Requires using DBeaver's SQL editor, EXPLAIN functionality, and schema tools
