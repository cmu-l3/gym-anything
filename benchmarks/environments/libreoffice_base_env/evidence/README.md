# LibreOffice Base Environment — Evidence Documentation

## Overview

This document provides evidence that the `libreoffice_base_env` environment was successfully
created, installed, configured, and that all 5 tasks are interactively completable.

**Application:** LibreOffice Base 7.3.7.2 with embedded HSQLDB 1.8
**Dataset:** Chinook digital music store database (real data from GitHub)
— 11 tables: Artist (275), Album (347), Track (3503), Customer (59), Invoice (412), InvoiceLine (2240), Employee (8), Genre (25), MediaType (5), Playlist (18), PlaylistTrack (8715)

---

## Environment Setup Evidence

### Phase 1: Installation (pre_start)
- LibreOffice Base 7.3 installed from Ubuntu packages
- Chinook SQLite database downloaded from GitHub (~1MB)
- Converted to LibreOffice Base ODB format via `create_chinook_odb.py`
- Key: HSQLDB 1.8 script initialization order: `CREATE SCHEMA PUBLIC AUTHORIZATION DBA` → `CREATE USER SA PASSWORD ""` → `GRANT DBA TO SA` → tables → inserts

### Phase 2: Configuration (post_start)
- LibreOffice registrymodifications.xcu pre-configured (no first-run wizard, Java enabled)
- chinook.odb copied to /home/ga/
- Warm-up launch performed to dismiss any remaining dialogs

### Screenshot: `tables_view.png`
All 11 Chinook tables visible in LibreOffice Base Tables panel. No errors.

### Screenshot: `final_state_all_tables.png`
Confirmed all 11 tables accessible with full data.

### Screenshot: `track_table_data.png`
Track table opened (window maximized) showing all 9 columns: TrackId, Name, AlbumId, MediaTypeId,
GenreId, Composer, Milliseconds, Bytes, UnitPrice. Navigation bar shows "1 of 3503" confirming
all 3,503 real music track records are loaded.

---

## Task Evidence

### Task 1: `create_table`
**Description:** Create a new table named 'Promotions' with 4 columns using Table Design view.

**Screenshot: `create_table_design.png`**
- Table Design view opened from the Tables section
- "PromotionId" entered in Field Name column
- Field Type set to "Integer [INTEGER]" — correct type for a primary key ID column
- Field Properties panel at bottom shows AutoValue, Entry required, Length=10
- Table Design view fully functional and interactive

**Setup Log Snippet:**
```
=== Setting up create_table task ===
Killing any running LibreOffice instances...
LibreOffice stopped.
Restoring fresh copy of chinook.odb...
chinook.odb restored.
Launching LibreOffice Base with: /home/ga/chinook.odb
Waiting for LibreOffice Base window (timeout: 45s)...
LibreOffice Base window found after 1s (WID: 35651709)
Dismissing any LibreOffice dialogs...
Dialog dismissal complete.
=== create_table task ready ===
```
**Pre-task setup time: ~1s** (warm: LO already installed, using savevm checkpoint)

---

### Task 2: `run_query`
**Description:** Create a SQL query named 'LongTracks' using SQL View that selects tracks > 5 min.

**Screenshot: `run_query_success.png`**
- SQL View opened from "Create Query in SQL View..."
- `SELECT Name FROM Artist WHERE ArtistId <= 10` typed and executed
- Results show 10 artist records (AC/DC, Accept, Aerosmith, etc.)

**Screenshot: `run_query_longtracks.png`**
- Full task query executed:
  `SELECT Name, Milliseconds, UnitPrice FROM Track WHERE Milliseconds > 300000 ORDER BY Milliseconds DESC`
- Results: 41 records returned with Name, Milliseconds, UnitPrice columns
- First row: "Occupation" — 5,286,953ms (~88 min), $1.99
- Query sorted correctly by Milliseconds DESC

**Setup Log Snippet:**
```
=== Setting up run_query task ===
LibreOffice Base window found after 1s (WID: ...)
=== run_query task ready ===
```

---

### Task 3: `create_form`
**Description:** Use Form Wizard to create 'Customer Entry Form' with 5 Customer fields.

**Screenshot: `create_form_wizard.png`**
- Form Wizard opened from "Use Wizard to Create Form..."
- "Table: Customer" selected from the dropdown
- All Customer fields visible in Available fields list:
  CustomerID, FirstName, LastName, Company, Address, City, State, Country, PostalCode
- (Scroll reveals: Phone, Fax, Email, SupportRepId)
- Wizard is fully interactive with field selection, layout choice, naming

**Setup Log Snippet:**
```
=== Setting up create_form task ===
LibreOffice stopped.
Restoring fresh copy of chinook.odb...
chinook.odb restored.
Launching LibreOffice Base with: /home/ga/chinook.odb
LibreOffice Base window found after 1s (WID: 8389510)
=== create_form task ready ===
```

---

### Task 4: `add_record`
**Description:** Open the Customer table and add a new customer record (CustomerId=60).

**Screenshot: `add_record_table_open.png`**
- Customer table opened in Table Data View by double-clicking in Tables panel
- Shows all 59 existing customer records
- All required columns visible: CustomerID, FirstName, LastName, Company, City, State, Country, PostalCode, Phone, Fax, Email, SupportRepId
- Navigation bar shows "1 of 59"

**Screenshot: `add_record_new_row.png`**
- Navigated to end of table (Customer table window maximized)
- Last data rows visible: rows 57-59 (Luis Rojas/Chile, Manoj Pareek/India, Puja Srivastava/India)
- Row 60 shows asterisk (*) indicator in row selector — the new empty record entry row
- Navigation bar shows "1 of 60" confirming cursor is on the new (empty) row

**Setup Log Snippet:**
```
=== Setting up add_record task ===
LibreOffice stopped.
Restoring fresh copy of chinook.odb...
chinook.odb restored.
Launching LibreOffice Base with: /home/ga/chinook.odb
LibreOffice Base window found after 1s (WID: 8388733)
=== add_record task ready ===
Agent should: double-click the Customer table to open it in datasheet view,
then scroll to the bottom and add a new row with CustomerId=60.
```

---

### Task 5: `create_report`
**Description:** Use Report Wizard to create 'Artist Catalog' report from Artist table.

**Screenshot: `create_report_wizard.png`**
- Report Wizard opened from "Use Wizard to Create Report..."
- 6-step wizard visible: Field selection, Labeling fields, Grouping, Sort options, Choose layout, Create report
- Table dropdown shows "Table: Album" (Agent would change to "Table: Artist")
- All Chinook tables available in dropdown for selection
- Layout options, sort options all available through wizard steps

**Setup Log Snippet:**
```
=== Setting up create_report task ===
LibreOffice stopped.
Restoring fresh copy of chinook.odb...
chinook.odb restored.
Launching LibreOffice Base with: /home/ga/chinook.odb
LibreOffice Base window found after 1s (WID: 8388733)
=== create_report task ready ===
```

**Note:** `ReportBuilderImplementation is unavailable` is a harmless warning — the built-in
Report Wizard (not the Report Builder extension) is used and works correctly.

---

## Technical Notes

### HSQLDB 1.8 Quirks Encountered and Fixed
1. **Script initialization order**: SA user must be created explicitly in script (not auto-created)
2. **Backslash escaping**: 4 Track records have `\` in names; must double-escape: `str(val).replace("\\", "\\\\")`
3. **ODB ZIP format**: `mimetype` entry must be FIRST in ZIP and STORED (not DEFLATED)
4. **No LIMIT support**: Use `WHERE id <= N` instead of `LIMIT N` for row-limiting queries

### Pre-task Setup Performance
All tasks use `setup_libreoffice_base_task()` which:
1. Kills any running LibreOffice instance
2. Restores a fresh copy of chinook.odb
3. Launches LibreOffice Base with the database
4. Waits for the window to appear (typically ~1s from warm savevm)
5. Dismisses any modal dialogs

**Typical pre-task time: ~12-15s total** (most time is in kill + restore + launch + wait)

---

## Final Clean Test Results

**Test:** `env.reset(seed=42, use_cache=False, use_savevm=True)`
**Result: PASSED**

```
[QemuApptainer] COW overlay created
[QemuApptainer] VNC: 6029, SSH: 2248
[QemuApptainer] SSH available!
[QemuApptainer] Setting up 2 mounts...
[QemuApptainer] VM ready! Resolution: (1920, 1080)
[gym-anything] Running pre_start hook...    # install LibreOffice + create ODB
[gym-anything] Running post_start hook...   # configure + warm-up
Profiling time for env setup: 74.31s
Reset completed in 75.0s
```

**Post-reset verification:**
- `chinook.odb`: 161,541 bytes ✓
- LibreOffice version: 7.3.7.2 ✓
- `create_table` task setup: "LibreOffice Base window found after 1s" ✓

**Screenshot: `final_clean_test_ready.png`**
LibreOffice Base open with chinook.odb, Forms section selected (default start state for all 5 tasks).
Note: All 5 tasks begin with the Forms section visible. Tasks that operate on other sections
(Tables for create_table/add_record, Queries for run_query, Reports for create_report) require
the agent to click the appropriate left-panel button to navigate to the correct section first.

---

## New Hard Tasks (Added 2026-03)

Five new "very_hard" tasks added targeting realistic professional workflows.
All use the same Chinook ODB and the same environment; all require 3+ distinct
application features and multi-step reasoning.

### Verification Architecture (All 5 New Tasks)

**Pattern 1 — Baseline recording:** `setup_task.sh` records the initial ODB state
to `/tmp/<task>_initial.json` *before* launching LibreOffice. Verifier subtracts
pre-existing objects so only new work counts.

**Pattern 8 — Anti-tamper:** Verifier independently copies `/home/ga/chinook.odb`
from the VM and re-parses it directly (not relying solely on the export JSON).

**Multi-criterion scoring:** Each task has 4–5 independent sub-criteria with a
70-point pass threshold. Partial credit is awarded at intermediate stages.

### Offline Verifier Test Results

File: `new_tasks_verifier_offline_tests.json`

All 15 scenarios (5 tasks × 3 scenarios) pass:

| Task | DO_NOTHING | PARTIAL | FULL |
|---|---|---|---|
| genre_revenue_queries | 0 pts ✓ | 25 pts ✓ | 100 pts ✓ |
| commission_tracking_system | 0 pts ✓ | 40 pts ✓ | 100 pts ✓ |
| customer_segmentation | 0 pts ✓ | 45 pts ✓ | 100 pts ✓ |
| playlist_analytics | 0 pts ✓ | 52 pts ✓ | 100 pts ✓ |
| media_library_management | 0 pts ✓ | 51 pts ✓ | 100 pts ✓ |

Run tests with: `python3 test_libreoffice_base_new_tasks.py`

---

### Task 6: `genre_revenue_queries`

**Occupation context:** Office Clerks, General (#1 LibreOffice Base users by GDP)
**Difficulty:** very_hard | Timeout: 600s | Max steps: 100

**Description:** Music store analyst creates two aggregate revenue queries
(GenreRevenue joining 3 tables with GROUP BY, CountryRevenue joining Customer+Invoice),
a RevenueTarget reference table (4+ rows), and a Revenue Analysis report.

**Scoring (100 pts):**
- GenreRevenue query with JOIN + GROUP BY + SUM: 25 pts
- CountryRevenue query with JOIN + GROUP BY + SUM + country grouping: 25 pts
- RevenueTarget table created: 20 pts
- RevenueTarget has 4+ rows: 15 pts
- Report with "revenue" in name: 15 pts

---

### Task 7: `commission_tracking_system`

**Occupation context:** Compensation, Benefits, and Job Analysis Specialists (#4 by GDP)
**Difficulty:** very_hard | Timeout: 600s | Max steps: 100

**Description:** HR analyst creates a CommissionRate table (with rates for sales reps
EmployeeId 3, 4, 5), a RepSalesTotal query (Employee+Customer+Invoice JOIN with GROUP BY),
a CommissionDue query (joins RepSalesTotal+CommissionRate with multiplication), and a
Commission Entry form.

**Scoring (100 pts):**
- CommissionRate table created: 20 pts
- Commission rates for EmployeeIds 3, 4, 5 present: 20 pts
- RepSalesTotal query (Employee+Invoice JOIN + GROUP BY): 25 pts
- CommissionDue query (references commission data): 20 pts
- Form containing "Commission": 15 pts

---

### Task 8: `customer_segmentation`

**Occupation context:** Office Clerks, General / Secretaries (#1/#3 by GDP)
**Difficulty:** very_hard | Timeout: 600s | Max steps: 100

**Description:** Marketing analyst creates a CustomerLifetimeValue query
(Customer+Invoice with SUM/COUNT/AVG + GROUP BY), a CustomerTier reference table
(4 tiers: Bronze/Silver/Gold/Platinum), a CustomerTierAssignment query (joins
CLV with CustomerTier), and a Customer Analysis report.

**Scoring (100 pts):**
- CustomerLifetimeValue query (Customer+Invoice JOIN + GROUP BY + aggregate): 25 pts
- CustomerTier table created: 20 pts
- CustomerTier has 4+ rows: 15 pts
- CustomerTierAssignment query (references customer + tier): 25 pts
- Report containing "customer": 15 pts

---

### Task 9: `playlist_analytics`

**Occupation context:** Library Technicians (#5 by GDP)
**Difficulty:** very_hard | Timeout: 600s | Max steps: 100

**Description:** Content curator creates a PlaylistSummary query
(Playlist+PlaylistTrack+Track with COUNT+SUM+GROUP BY), a TopArtistsInPlaylists query
(Artist+Album+Track+PlaylistTrack with COUNT DISTINCT), a PlaylistTag table (5+ rows),
and a Playlist Tagger form.

**Scoring (100 pts):**
- PlaylistSummary query (Playlist+Track JOIN + GROUP BY + COUNT): 25 pts
- TopArtistsInPlaylists query (Artist+PlaylistTrack JOIN + GROUP BY + COUNT): 25 pts
- PlaylistTag table created: 20 pts
- PlaylistTag has 5+ rows: 15 pts
- Form containing "playlist": 15 pts

---

### Task 10: `media_library_management`

**Occupation context:** Library Technicians (#5) / Library Science Teachers (#7)
**Difficulty:** very_hard | Timeout: 600s | Max steps: 100

**Description:** Digital media librarian creates a FullTrackCatalog query (5-table JOIN:
Track+Album+Artist+Genre+MediaType), a GenreMediaBreakdown query (Genre+Track+MediaType
with GROUP BY genre+mediatype), a TrackReview table (5+ rows with ratings 1–5 and valid
Chinook TrackIds 1–3503), and a Media Catalog report.

**Scoring (100 pts):**
- FullTrackCatalog query (5 tables, 4+ JOINs): 25 pts
- GenreMediaBreakdown query (genre+media GROUP BY + COUNT/SUM): 20 pts
- TrackReview table created: 20 pts
- TrackReview has 5+ rows with valid ratings 1–5: 20 pts
- Report with "catalog" or "media" in name: 15 pts
