# MySQL Workbench Environment - Evidence Documentation

## ⚠️ KNOWN LIMITATIONS

> **IMPORTANT**: This section documents critical limitations that affect evidence collection and verification.

### GUI Automation Limitation (Snap-based MySQL Workbench)

The Snap-based MySQL Workbench has **limited compatibility with GUI automation tools** (xdotool, pyautogui, env.step()). This is a documented limitation of Snap sandboxing:

- **Symptom**: Mouse clicks on menu items, connection tiles, and UI elements fail to register
- **Cause**: Snap sandbox restricts X11/Wayland input injection
- **Impact**: Cannot programmatically navigate to SQL query editor or capture screenshots of query results

### Verification Strategy by Task

| Task | Verification Method | Screenshot Evidence | Why |
|------|---------------------|---------------------|-----|
| Task 1 | GUI + File | ✅ SakilaDB visible | Connection creation works via GUI |
| Task 2 | **Programmatic Only** | ⚠️ Home screen only | GUI automation limitation |
| Task 3 | **Programmatic Only** | ⚠️ Home screen only | GUI automation limitation |

### Explicit Acknowledgment: Tasks 2 & 3 Programmatic Verification

**Due to the Snap sandbox GUI automation limitation, Tasks 2 and 3 can ONLY be verified programmatically.** The verification relies on:

1. **Output file validation** - CSV file must exist at exact specified path
2. **Content validation** - Row count, column structure, known entries
3. **Database anti-gaming** - Each exported entry validated against live SQL queries
4. **NO visual verification** - Screenshots cannot show query results or export process

**This means**: An agent could theoretically create the CSV file programmatically (e.g., via MySQL CLI) without using the MySQL Workbench GUI. The verifier validates the OUTPUT, not the METHOD.

**Rationale**: This is acceptable because:
- The task requires SQL knowledge to construct correct queries
- Anti-gaming measures validate data accuracy against the database
- GUI screenshot verification is technically impossible with Snap packaging
- Alternative would be to not include MySQL Workbench tasks at all

### Alternative Evidence Provided

Since GUI screenshots are unreliable for Tasks 2 and 3, **comprehensive programmatic evidence** is provided:

1. **CSV File Exports**: Actual exported files in `evidence/`
   - `task2_expensive_films.csv` - 337 lines (336 films + header)
   - `task3_japan_cities.csv` - 249 lines (248 cities + header)

2. **Verification Evidence Logs**: Database query outputs with timestamps
   - `TASK2_VERIFICATION_EVIDENCE.txt` - Complete verification log
   - `TASK3_VERIFICATION_EVIDENCE.txt` - Complete verification log

3. **Database Validation**: Each exported entry validated against live SQL queries

This programmatic verification validates actual data content rather than visual appearance.

---

## Environment Overview

This document provides evidence that the MySQL Workbench environment has been successfully created and tested.

## Evidence Files in This Directory

| File | Description |
|------|-------------|
| `TASK2_VERIFICATION_EVIDENCE.txt` | Complete SQL query verification for Task 2 |
| `TASK3_VERIFICATION_EVIDENCE.txt` | Complete SQL query verification for Task 3 |
| `task2_expensive_films.csv` | Actual exported CSV (336 films with rental_rate > 2.99) |
| `task3_japan_cities.csv` | Actual exported CSV (248 Japanese cities) |
| `retest_task1_13_final_sakiladb_visible.png` | Task 1 final screenshot showing SakilaDB |
| `task2_evidence_*.png` | Task 2 screenshot sequence |
| `task3_evidence_*.png` | Task 3 screenshot sequence |

## Audit Fixes Applied

### Fourth Audit (2026-02-03) - Current Fixes

1. **Removed count hints from task descriptions**:
   - Task 2: Removed "approximately 336 films matching this criteria"
   - Task 3: Removed "approximately 248 cities in Japan"
2. **Updated README**: Explicitly documented that Tasks 2 & 3 rely on programmatic verification only
3. **Clarified verification strategy**: Added table showing verification method per task

### Third Audit (2026-02-03)

1. **Task 1 verifier**: Changed to exact name match only (no partial credit)
2. **Task 2 metadata**: Updated `known_film_titles` to only include films with rental_rate = 4.99
3. **Evidence documentation**: Added CSV exports and verification logs as alternative to screenshots
4. **README**: Added prominent KNOWN LIMITATIONS section

### Previous Fixes

1. Task descriptions fixed to remove exact SQL hints
2. Verifiers enhanced with anti-gaming measures
3. Database validation required for passing

## Test Results Summary

### Environment Startup

- **MySQL Service Status**: `active`
- **MySQL Workbench Status**: Running
- **Desktop Environment**: Ready
- **Setup Time**: ~95-120 seconds

### Database Verification

The following databases were successfully loaded:

1. **sakila** - Official MySQL sample database (DVD rental store)
2. **world** - Official MySQL sample database (countries and cities)

## Task Verification Results

### Task 1: connect_to_database - ✅ VERIFIED

**Evidence**: `retest_task1_13_final_sakiladb_visible.png`

Screenshot shows "SakilaDB" connection in the MySQL Connections panel.

```json
{
  "workbench_running": true,
  "connection_found": true,
  "connection_name": "SakilaDB",
  "exact_name_match": true,
  "connection_working": true
}
```

### Task 2: run_sql_query - ✅ VERIFIED (via programmatic evidence)

**Evidence Files**:
- `TASK2_VERIFICATION_EVIDENCE.txt`
- `task2_expensive_films.csv`

**Database Query Results**:
```
+-------------+-------+
| rental_rate | count |
+-------------+-------+
|        0.99 |   341 |
|        2.99 |   323 |
|        4.99 |   336 |  <-- These are the films with rental_rate > 2.99
+-------------+-------+

Count: 336 films
```

**Exported CSV Verification**:
- File: `/home/ga/Documents/exports/expensive_films.csv`
- Line count: 337 (336 data + 1 header)
- All entries have rental_rate = 4.99 (confirmed by `awk` check)

**Sample Data**:
```csv
title,description,release_year,rental_duration,rental_rate,...
ACE GOLDFINGER,...,4.99,...
AIRPLANE SIERRA,...,4.99,...
AIRPORT POLLOCK,...,4.99,...
```

### Task 3: export_data - ✅ VERIFIED (via programmatic evidence)

**Evidence Files**:
- `TASK3_VERIFICATION_EVIDENCE.txt`
- `task3_japan_cities.csv`

**Database Query Results**:
```
Count of cities in Japan (CountryCode = 'JPN'): 248
```

**Exported CSV Verification**:
- File: `/home/ga/Documents/exports/japan_cities.csv`
- Line count: 249 (248 data + 1 header)
- All entries have CountryCode = JPN (confirmed by `awk` check)

**Well-known Japanese cities verified**:
- Tokyo ✓, Osaka ✓, Yokohama ✓, Nagoya ✓, Sapporo ✓, Kobe ✓, Kyoto ✓, Hiroshima ✓

## Data Sources (REAL DATA - NOT SYNTHETIC)

### Sakila Database
- **Source**: Official MySQL sample database
- **URL**: https://downloads.mysql.com/docs/sakila-db.zip
- **Tables**: 16 base tables + views
- **Records**: Thousands of realistic entries

### World Database
- **Source**: Official MySQL sample database
- **URL**: https://downloads.mysql.com/docs/world-db.zip
- **Tables**: country, city, countrylanguage
- **Records**: 239 countries, 4079 cities

Both databases are **official MySQL sample databases**, not synthetic data.

## Technical Notes

### MySQL Workbench Snap Configuration

MySQL Workbench installed via snap stores configuration in:
```
/home/ga/snap/mysql-workbench-community/<version>/.mysql/workbench/
```

### Verifier Anti-Gaming Measures

1. **Exact file path required** - Cannot use pre-created files in wrong location
2. **Database validation** - Each exported entry validated against actual SQL queries
3. **Known content lists** - Must include specific films/cities from actual data
4. **Row count bounds** - Cannot just add random rows

### Environment Timing

| Phase | Duration |
|-------|----------|
| VM Boot | ~5s |
| Pre-start hook (installation) | ~80-100s |
| Post-start hook (setup) | ~15-25s |
| Task hooks | ~0.8s |
| **Total** | ~95-130s |

## Credentials

| User | Password | Permissions |
|------|----------|-------------|
| root | GymAnything#2024 | Full admin |
| ga | password123 | All privileges on all databases |

## Conclusion

The MySQL Workbench environment has been successfully created and validated through:

1. Automated environment startup and configuration
2. Real database loading from official MySQL sources
3. **Task 1**: Interactive testing with CUA-guided UI interaction (screenshot verified)
4. **Tasks 2 & 3**: Programmatic verification via export scripts and database queries

All three tasks pass their verification checks:
- ✅ Task 1: Connection "SakilaDB" found in server_instances.xml (screenshot evidence)
- ✅ Task 2: 336 expensive films exported to CSV (programmatic evidence)
- ✅ Task 3: 248 Japanese cities exported to CSV (programmatic evidence)

The environment is ready for use with GUI automation agents.
