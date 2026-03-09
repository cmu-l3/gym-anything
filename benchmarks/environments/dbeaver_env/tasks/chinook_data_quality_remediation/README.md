# Task: Chinook Data Quality Remediation

## Domain
Software Quality Assurance — Database Integrity Audit

## Occupation Context
**Software QA Analysts and Testers** (GDP impact: $468M, importance=99) use DBeaver to
"verify data integrity, set up test data, and validate backend state changes." This task
reflects the real QA workflow of auditing a database after a failed import: identifying
orphaned records, fixing null data, and documenting all findings.

## Goal
Perform a comprehensive data integrity audit on a copy of the Chinook database that was
corrupted during a data migration. Fix identified issues and produce a formal audit report.

## Database: ChinookAudit
- **Location**: `/home/ga/Documents/databases/chinook_audit.db`
- **Source**: Copy of Chinook digital media store database with introduced data quality issues
- **Connection name**: `ChinookAudit`

## Introduced Data Quality Issues (set up before task start)
1. **Orphaned invoice_items**: Several invoices were deleted without cascading to invoice_items,
   leaving invoice_items rows with InvoiceId values that reference non-existent invoices.
2. **NULL Rock composers**: A batch update accidentally set Composer=NULL for a subset of
   Rock genre tracks (TrackId range 1–200 with Rock genre).
3. **Invalid email addresses**: Some customer email addresses are malformed (missing '@' or
   missing '.' after '@').

## Expected Deliverables

### 1. DBeaver Connection
- Name: `ChinookAudit` (exact, case-sensitive)
- Driver: SQLite
- Path: `/home/ga/Documents/databases/chinook_audit.db`

### 2. Database Fixes (in chinook_audit.db)
- DELETE all orphaned invoice_items (InvoiceId not in invoices)
- UPDATE Composer='Unknown' for all Rock tracks with NULL Composer

### 3. Audit Report: `/home/ga/Documents/exports/quality_audit.csv`
Required columns: `IssueType`, `RecordsAffected`, `TableName`, `Action`
Required rows:
- `orphaned_invoice_items` — count deleted, table=invoice_items, action=deleted
- `null_rock_composers` — count updated, table=tracks, action=updated
- `invalid_emails` — count found, table=customers, action=documented

## Verification Strategy

| Criterion | Points | Check |
|-----------|--------|-------|
| DBeaver 'ChinookAudit' connection exists | 15 | data-sources.json parsed |
| Orphaned invoice_items count = 0 (all fixed) | 25 | sqlite3 query on audit DB |
| NULL Rock composer count = 0 (all fixed) | 25 | sqlite3 query on audit DB |
| quality_audit.csv exists with 3 issue rows | 20 | file existence + content |
| CSV RecordsAffected values match ground truth | 15 | value comparison |

**Pass threshold: 60 points**

## Difficulty Factors
- Must discover the foreign key relationship between invoice_items and invoices
- Must identify which Genre is 'Rock' (via genre table join, not hardcoded ID)
- Must identify email validation logic without being given the exact SQL
- Three independent subtasks (delete, update, report) each requiring different SQL patterns
- Must produce properly formatted CSV with specific column names

## Schema Reference
```sql
CREATE TABLE invoices (InvoiceId INTEGER PRIMARY KEY, CustomerId INTEGER, InvoiceDate TEXT, Total REAL, ...)
CREATE TABLE invoice_items (InvoiceLineId INTEGER PRIMARY KEY, InvoiceId INTEGER, TrackId INTEGER, UnitPrice REAL, Quantity INTEGER)
CREATE TABLE tracks (TrackId INTEGER PRIMARY KEY, Name TEXT, Composer TEXT, GenreId INTEGER, ...)
CREATE TABLE genres (GenreId INTEGER PRIMARY KEY, Name TEXT)
CREATE TABLE customers (CustomerId INTEGER PRIMARY KEY, Email TEXT, FirstName TEXT, LastName TEXT, ...)
```
