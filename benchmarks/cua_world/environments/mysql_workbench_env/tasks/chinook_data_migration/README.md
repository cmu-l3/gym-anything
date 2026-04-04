# Task: chinook_data_migration

## Domain Context
Software Developers frequently encounter data integrity issues introduced by ETL jobs, batch
imports, or migration scripts. A canonical DBA/developer workflow is: identify the corrupted
records, write corrective SQL, then build the reporting layer (views, indexes) on clean data.

## Occupation Context
Primary occupation: Software Developers ($3.4B GDP)
Rationale: "Essential for querying, designing, and managing application databases."
Secondary: Business Intelligence Analysts ($1.3B GDP)

## Task Goal
1. Fix 15 Invoice records with NULL BillingAddress (copy from Customer.Address)
2. Fix 3 InvoiceLine records with wrong UnitPrice (sync to Track.UnitPrice)
3. Create view v_sales_by_genre (Genre + Track + InvoiceLine + Invoice join, total sales per genre)
4. Add index idx_invoiceline_trackid on InvoiceLine(TrackId)
5. Export v_sales_by_genre to /home/ga/Documents/exports/chinook_genre_sales.csv

## Starting State (set up by setup_task.sh)
- Chinook database downloaded from lerocha/chinook-database (real digital music store data)
- InvoiceIds 1-15: BillingAddress set to NULL
- InvoiceLineIds 1, 50, 100: UnitPrice set to 99.99 (wrong, doesn't match Track table)
- No v_sales_by_genre view
- No idx_invoiceline_trackid index

## Data Source
Chinook Sample Database by Luis Rocha (lerocha/chinook-database on GitHub).
A realistic digital music store database modeled after the iTunes digital music store.
Contains: Artist, Album, Track, Genre, InvoiceLine, Invoice, Customer, Employee.
Real-world structure with 412 invoices, 2240 invoice lines, 3503 tracks, 25 genres.

## Difficulty: hard
Agent is told:
- Which issues exist (NULL BillingAddress, wrong UnitPrice) and their counts
- What to create (view name, index name, output file path)
Agent must determine:
- The correct SQL UPDATE queries to fix each issue
- The correct JOIN logic for v_sales_by_genre
- How to navigate MySQL Workbench to create indexes and views

## Scoring (100 points)
- NULL BillingAddress fixed (0 remaining): 25 pts
- Wrong UnitPrice InvoiceLines fixed (0 remaining): 25 pts
- v_sales_by_genre view with >= 10 genres: 25 pts
- idx_invoiceline_trackid index created: 15 pts
- CSV export with >= 10 rows: 10 pts
**Pass threshold: 60 points**

## Verification Strategy
- Queries information_schema.VIEWS and information_schema.STATISTICS
- Checks Invoice and InvoiceLine tables for remaining data issues
- Checks CSV file existence, row count, and modification timestamp vs task start

## Feature Coverage
- SQL Query Editor (UPDATE with JOIN, CREATE VIEW)
- Table Editor / Index management
- Schema browser (understanding Chinook schema)
- Data Export (CSV from view)
- Query writing and execution
