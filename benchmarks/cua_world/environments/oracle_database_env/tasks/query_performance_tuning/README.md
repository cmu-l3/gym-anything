# Task: Oracle Query Performance Tuning with Real OpenFlights Data

## Overview

A GIS technologist at a logistics firm has loaded the full OpenFlights dataset into Oracle — 14,000+ airports and 67,000+ flight routes. A colleague wrote 5 analytical queries that work correctly but perform full table scans on every execution, causing unacceptable latency in production reporting.

## Goal

1. Analyze the 5 slow queries in `/home/ga/Desktop/slow_queries.sql` using Oracle's EXPLAIN PLAN
2. Create at least **4 appropriate indexes** on the `AIRPORTS` and `FLIGHT_ROUTES` tables to eliminate full table scans
3. Save optimized versions of all 5 queries (index-aware, semantically equivalent) to `/home/ga/Desktop/optimized_queries.sql`, with queries separated by semicolons

## Environment

- **Database**: Oracle XE 21c (container: `oracle-xe`)
- **Schema**: HR (user: `hr`, password: `hr123`)
- **PDB**: XEPDB1 (port 1521)
- **Client**: DBeaver CE (pre-configured)

## Tables

### AIRPORTS (14,110 rows)
| Column | Type | Description |
|--------|------|-------------|
| AIRPORT_ID | NUMBER(6) PK | OpenFlights airport ID |
| NAME | VARCHAR2(200) | Airport name |
| CITY | VARCHAR2(100) | City |
| COUNTRY | VARCHAR2(100) | Country name |
| IATA_CODE | VARCHAR2(3) | 3-letter IATA code |
| ICAO_CODE | VARCHAR2(4) | 4-letter ICAO code |
| LATITUDE | NUMBER(10,6) | Latitude |
| LONGITUDE | NUMBER(10,6) | Longitude |
| ALTITUDE_FT | NUMBER(6) | Altitude in feet |
| TIMEZONE_OFFSET | NUMBER(4,1) | UTC offset |

### FLIGHT_ROUTES (67,663 rows)
| Column | Type | Description |
|--------|------|-------------|
| ROUTE_ID | NUMBER PK | Auto-generated |
| AIRLINE_CODE | VARCHAR2(3) | IATA airline code |
| AIRLINE_ID | NUMBER | Airline ID |
| SRC_IATA | VARCHAR2(4) | Source airport IATA |
| SRC_AIRPORT_ID | NUMBER | Source airport ID |
| DST_IATA | VARCHAR2(4) | Destination IATA |
| DST_AIRPORT_ID | NUMBER | Destination ID |
| CODESHARE | VARCHAR2(1) | 'Y' = codeshare flight |
| STOPS | NUMBER(2) | Number of stops |
| EQUIPMENT | VARCHAR2(50) | Aircraft type codes |

## The 5 Slow Queries

1. **Country filter** — find all US airports ordered by city (full scan on AIRPORTS)
2. **Country + altitude filter** — high-altitude airports in Canada/Russia (no composite index)
3. **Route count per hub** — join AIRPORTS to FLIGHT_ROUTES on IATA code (no index on SRC_IATA)
4. **Direct route lookup** — find routes between JFK and LAX (no composite index on src/dst)
5. **Codeshare analysis** — airports with most codeshare departures (no index on CODESHARE)

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Data intact (airports ≥14k, routes ≥67k) | 5 |
| 1st new index created | 10 |
| 2nd new index created | 8 |
| 3rd new index created | 7 |
| 4th new index created | 5 |
| At least one AIRPORTS index covers country/altitude_ft/iata_code | 10 |
| At least one FLIGHT_ROUTES index covers src_iata/dst_iata/codeshare | 10 |
| optimized_queries.sql exists on Desktop | 10 |
| File contains ≥5 SQL statements | 15 |
| File references key columns (country, src_iata, etc.) | 10 |
| EXPLAIN PLAN shows index access for country filter (bonus) | 10 |
| **Total** | **100** |

Pass threshold: 55 points

## Verification Strategy

The verifier:
1. Counts indexes in `USER_INDEXES` where `TABLE_NAME IN ('AIRPORTS','FLIGHT_ROUTES')` and compares to baseline (system-created indexes before task)
2. Reads `USER_IND_COLUMNS` to verify indexed column relevance
3. Runs `EXPLAIN PLAN` for the country filter query and checks for INDEX operations
4. Checks `/home/ga/Desktop/optimized_queries.sql` for size, statement count, and content

## Tips

- Use `EXPLAIN PLAN FOR <query>; SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);` in DBeaver
- For the country filter: a B-tree index on `AIRPORTS(COUNTRY)` will eliminate the full scan
- For route lookups: a composite index on `FLIGHT_ROUTES(SRC_IATA, DST_IATA)` covers both queries 3 and 4
- For codeshare: a function-based or simple index on `FLIGHT_ROUTES(CODESHARE)` helps query 5
- Run `EXEC DBMS_STATS.GATHER_TABLE_STATS('HR', 'AIRPORTS')` after creating indexes to update statistics
