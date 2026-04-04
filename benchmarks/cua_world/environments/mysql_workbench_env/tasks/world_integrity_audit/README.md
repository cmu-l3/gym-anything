# Task: world_integrity_audit

## Domain Context
Database Administrators regularly perform data quality audits after failed batch imports or
ETL jobs. A common scenario: orphaned records with invalid foreign keys, zero-value entries
from placeholder rows, and exact duplicate records. The DBA must independently discover all
these issues using SQL diagnostic queries, decide on the correct remediation, execute it, and
produce a clean output for downstream use.

## Occupation Context
Primary occupation: Database Administrators ($668M GDP)
Rationale: "The primary interface for creating, configuring, querying, and managing database
structures and user access." — master_dataset.csv
Secondary: Computer Systems Analysts ($1B GDP)

## Task Goal
The agent must independently discover and fix:
1. 35 cities with CountryCode='ZZZ' (orphaned FK violations — no matching country)
2. 10 cities with CountryCode='ZZX' (orphaned FK violations — different bad batch)
3. 8 cities with Population=0 (invalid data — should be deleted)
4. 3 duplicate city records (London, Paris, Berlin duplicated by failed import)

Then export: all South American cities to /home/ga/Documents/exports/south_america_cities.csv

## Starting State (set up by setup_task.sh)
- World DB augmented with 53 injected bad records (35 ZZZ + 10 ZZX + 8 zero-pop + 3 dupes)
- Task description only says "audit for integrity violations" — agent must discover specifics
- No export CSV exists

## Data Source
World sample database — official MySQL sample database with 4079 real cities.
All injected bad records are clearly identifiable as invalid via SQL queries.
Bad record injection technique per lesson 38: running real SQL against a real system.

## Difficulty: very_hard
Agent is told only:
- The database has been corrupted by a failed import
- To audit for integrity violations and data anomalies
- The type of issues to look for (but NOT which specific records or codes)
- The output file path

Agent must independently:
- Run diagnostic queries to discover orphaned records
- Discover the invalid country codes ('ZZZ', 'ZZX')
- Discover zero-population records
- Discover duplicate records
- Decide on correct remediation (DELETE strategy)
- Execute multi-step cleanup
- Join with country table to get South America cities and export

## Scoring (100 points)
- All 35 ZZZ orphan cities removed: 25 pts
- All 10 ZZX orphan cities removed: 15 pts
- All 8 zero-population cities removed: 15 pts
- All duplicate city records removed: 15 pts
- South America CSV with >= 400 rows matching DB state: 30 pts
**Pass threshold: 60 points**

## Verification Strategy
- Counts remaining orphaned cities (LEFT JOIN city to country WHERE code IS NULL)
- Counts remaining ZZZ and ZZX specifically
- Counts remaining zero-population cities
- Counts remaining duplicates (GROUP BY Name+CountryCode+District HAVING COUNT>1)
- Checks CSV file existence, row count vs DB count, and modification timestamp

## Feature Coverage
- SQL Query Editor (diagnostic LEFT JOIN queries, DELETE statements)
- Schema browser (understanding world DB FK relationships)
- Query execution and result analysis
- Data Export (CSV with JOIN to country table)
- Multi-step data remediation workflow
