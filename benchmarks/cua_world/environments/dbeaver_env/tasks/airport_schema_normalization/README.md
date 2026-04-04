# Task: Airport Schema Normalization

## Domain
Database Architecture — Schema Design and Data Migration

## Occupation Context
**Database Architects** (GDP impact: $490M, importance=94) use DBeaver for "daily interaction,
query testing, and database administration tasks." **Computer Systems Analysts** (importance=99)
use it to "validate migrations, and design new schemas." This task reflects the real workflow of
receiving a flat denormalized dataset and designing a proper relational schema, then migrating
the data — a core database architecture competency.

## Goal
Transform a flat-table airport database (real OpenFlights data, ~7000 airports) into a properly
normalized 3NF schema. Create three normalized tables, migrate all data, and write a validation
report confirming the migration.

## Database: Airports
- **Location**: `/home/ga/Documents/databases/airports_flat.db`
- **Source**: OpenFlights global airport database (CC BY 2.0 License)
  - Data URL: https://raw.githubusercontent.com/jpatokal/openflights/master/data/airports.dat
- **Flat table**: `airports_raw` (~7,000 rows, 14 columns)

### Current Flat Schema (airports_raw)
```
airport_id, name, city, country, iata_code, icao_code,
latitude, longitude, altitude, timezone_offset, dst_type,
tz_name, type, source
```

### Target Normalized Schema (3NF)
```sql
CREATE TABLE countries (country_name TEXT PRIMARY KEY);
CREATE TABLE timezones (tz_name TEXT PRIMARY KEY, timezone_offset REAL, dst_type TEXT);
CREATE TABLE airports (
    airport_id INTEGER PRIMARY KEY,
    name TEXT, city TEXT, iata_code TEXT, icao_code TEXT,
    latitude REAL, longitude REAL, altitude INTEGER,
    type TEXT, source TEXT,
    country_name TEXT REFERENCES countries(country_name),
    tz_name TEXT REFERENCES timezones(tz_name)
);
```

## Expected Deliverables

### 1. DBeaver Connection
- Name: `Airports` (exact)
- Driver: SQLite
- Path: `/home/ga/Documents/databases/airports_flat.db`

### 2. Three New Tables
Created in the same `airports_flat.db` file via SQL in DBeaver.

### 3. Data Migration
All rows from `airports_raw` migrated into the three normalized tables using INSERT...SELECT.

### 4. Validation Report: `/home/ga/Documents/exports/normalization_report.txt`
```
ORIGINAL_COUNT: 7184
AIRPORTS_TABLE_COUNT: 7184
COUNTRIES_COUNT: 241
TIMEZONES_COUNT: 437
MIGRATION_VALID: YES
```

## Verification Strategy

| Criterion | Points | Check |
|-----------|--------|-------|
| DBeaver 'Airports' connection exists | 10 | data-sources.json parsed |
| countries table exists with correct count | 20 | sqlite3 COUNT(*) |
| timezones table exists with correct count | 15 | sqlite3 COUNT(*) |
| airports table exists with correct count | 20 | sqlite3 COUNT(*) == ORIGINAL_COUNT |
| normalization_report.txt at correct path | 20 | file existence + content parsing |
| MIGRATION_VALID = YES in report | 15 | text search in report |

**Pass threshold: 60 points**

## Difficulty Factors
- Must understand 3NF normalization principles to identify which columns belong to each table
- Must write DDL (CREATE TABLE) from scratch — schema not given as SQL
- Must write data migration queries (INSERT ... SELECT with DISTINCT for dimension tables)
- Must handle NULL/missing values in tz_name and country fields gracefully
- Must produce a report with specific labels — requires synthesizing multiple query results
- Requires using multiple DBeaver features: SQL editor, schema browser, result export
