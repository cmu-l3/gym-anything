# Chinook Partner Sales ETL (`chinook_partner_sales_etl@1`)

## Overview
This task evaluates the agent's ability to perform a common ETL (Extract, Transform, Load) workflow using DBeaver. The agent must import an external CSV file into a staging table, perform data validation using multi-table SQL joins, populate a normalized destination table with resolved foreign keys, and export rejected records for review.

## Rationale
**Why this task is valuable:**
- **Tests Data Import UI:** Requires using DBeaver's "Import Data" wizard or scripting CSV imports.
- **Tests Complex Data Validation:** Validating records requires joining across 4 tables (`tracks` → `albums` → `artists` and `customers`) to resolve IDs.
- **Tests Logic Branching:** The agent must separate "good" data (to load) from "bad" data (to report), a critical data engineering skill.
- **Real-world Context:** "Partner data integration" is a frequent task where dirty external data must be mapped to internal schema IDs before insertion.

**Real-world Context:**
A third-party music festival ("Rock on the Range") sold digital downloads of Chinook tracks as part of a promotion. They have provided a CSV file of these sales. The Data Team needs to ingest this data into the Chinook database, but only for transactions that can be matched to **existing customers** and **valid tracks**. Any unmatched records must be flagged for manual review.

## Task Description

**Goal:** Import the festival sales CSV, filter the data to populate a normalized `valid_festival_sales` table, and export any unmatched records to an exception report.

**Starting State:**
- DBeaver is open.
- The standard Chinook database is at `/home/ga/Documents/databases/chinook.db`.
- A raw data file exists at `/home/ga/Documents/data/festival_sales.csv`.
- The CSV contains: `SaleDate`, `UserEmail`, `SongTitle`, `ArtistName`, `Price`.

**Expected Actions:**
1. **Connect** to the Chinook database.
2. **Import** the `/home/ga/Documents/data/festival_sales.csv` file into a new table named `festival_sales_import` (the staging table).
   - *Tip:* Ensure columns are imported with appropriate text/real types.
3. **Create** a destination table named `valid_festival_sales` with columns:
   - `Id` (Integer Primary Key, auto-increment)
   - `SaleDate` (Text)
   - `CustomerId` (Integer)
   - `TrackId` (Integer)
   - `Price` (Real)
4. **Populate** `valid_festival_sales` by selecting rows from the staging table where:
   - `UserEmail` matches an existing `customers.Email`.
   - `SongTitle` matches `tracks.Name` AND `ArtistName` matches the linked `artists.Name`.
   - *Note:* Matches should be exact.
5. **Export** a CSV report of **rejected rows** to `/home/ga/Documents/exports/festival_sales_exceptions.csv`.
   - Rejected rows are those where the Email was unknown OR the Song/Artist combination could not be resolved.
   - The CSV should contain the original columns from the import.

**Final State:**
- `festival_sales_import` exists containing the raw CSV data.
- `valid_festival_sales` exists containing only the clean, mapped data with valid foreign keys.
- `festival_sales_exceptions.csv` exists containing only the rows that failed validation.

## Verification Strategy

### Primary Verification: Database State & Output File
The verifier checks the SQLite database and the exported CSV to ensure data was correctly filtered and transformed.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| **Staging Table Import** | 20 | Table `festival_sales_import` exists and row count matches CSV. |
| **Destination Schema** | 10 | Table `valid_festival_sales` exists with correct columns (`CustomerId`, `TrackId`, etc.). |
| **Data Cleaning Logic** | 30 | `valid_festival_sales` contains *only* valid matches (verified by joining back to source tables). |
| **Foreign Key Resolution** | 10 | `CustomerId` and `TrackId` values in destination table are correct integers, not NULL. |
| **Exception Report Exists** | 10 | `festival_sales_exceptions.csv` exists at the correct path. |
| **Exception Content** | 20 | Exception file contains exactly the rows that are NOT in the valid table. |
| **Total** | **100** | |

**Pass Threshold:** 70 points