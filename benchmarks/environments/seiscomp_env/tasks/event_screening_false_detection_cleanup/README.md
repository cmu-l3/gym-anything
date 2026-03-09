# Event Screening and False Detection Cleanup (`event_screening_false_detection_cleanup@1`)

## Task Overview

A seismologist cleans a contaminated SeisComP database that contains a genuine M7.5 Noto Peninsula earthquake alongside three false detection events injected during a maintenance window. The operator must review the event list in scolv, identify the false detections by their unrealistic locations, low phase counts, and small magnitudes, delete them from the database, and export a verified bulletin of the remaining real event.

## Domain Context

**Occupation:** Geoscientists / Seismologists (SOC 19-2042.00)

Automatic event detection pipelines can produce false triggers -- spurious events caused by noise, calibration pulses, or station malfunctions. Quality control is a critical seismological task: analysts must distinguish real earthquakes from false detections using criteria such as geographic plausibility, number of associated phase picks, and magnitude consistency. Maintaining a clean event catalog is essential for downstream seismological research and public alerting.

**Environment:** SeisComP with MariaDB database (`mysql -u sysop -psysop seiscomp`), configuration at `/home/ga/seiscomp/etc/`.

## Goal Description

1. Open scolv and review the event list, which contains 4 events: 1 real earthquake and 3 false detections.
2. Identify the 3 false detections based on these characteristics:
   - **False detection 1 (false_det_001):** Mid-Pacific location (lat 5.0, lon 170.5), M1.3, 2 picks
   - **False detection 2 (false_det_002):** South Pacific location (lat -45.0, lon -175.0), M0.8, 2 picks
   - **False detection 3 (false_det_003):** North Atlantic location (lat 65.0, lon -30.5), M1.6, 2 picks
3. Delete all 3 false detections from the database via scolv or database commands.
4. Preserve the genuine Noto Peninsula earthquake (M7.5, lat ~37.5, lon ~137.3, many associated picks).
5. Export a bulletin of the remaining verified event to `/home/ga/Desktop/verified_events.txt` using `scbulletin`.

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| False events removed | 40 | All 3 false detection events deleted from the database (~13 pts each) |
| Real event preserved | 25 | The genuine Noto M7.5 earthquake is still present in the database (not accidentally deleted) |
| Bulletin with real event | 20 | Bulletin file at `/home/ga/Desktop/verified_events.txt` exists and contains identifiable real event data |
| Bulletin clean | 15 | Bulletin does not contain any false event references |

**Pass threshold:** 60 / 100

## Verification Strategy

The post-task `export_result.sh` script queries the database and filesystem:

- Counts total events and compares to the initial count of 4.
- Checks whether each false event (by origin location matching) still exists in the database.
- Verifies the real Noto event is preserved by checking for an origin near lat ~37.5, lon ~137.3 with magnitude >= 7.0.
- Reads the bulletin file and checks for real event identifiers (Noto, M7.5, lat ~37) and false event identifiers (false_det, Pacific, Atlantic, M < 2.0 magnitudes).
- A do-nothing guard returns score 0 if event count has not changed and no bulletin exists.
- A penalty applies if the real event was accidentally deleted.

The `verifier.py::verify_event_screening_false_detection_cleanup` function consumes the exported JSON and computes the weighted score.

## Schema and Data Reference

**Real event:** Noto Peninsula, Japan -- 2024-01-01, M7.5, lat ~37.5, lon ~137.3, many associated phase picks, manual evaluation.

**False events (injected by setup):**

| ID | Location | Lat | Lon | Depth | Mag | Picks | Description |
|----|----------|-----|-----|-------|-----|-------|-------------|
| false_det_001 | Mid-Pacific | 5.0 | 170.5 | 33 km | M1.3 | 2 | Ocean, far from stations |
| false_det_002 | South Pacific | -45.0 | -175.0 | 10 km | M0.8 | 2 | Ocean, far from stations |
| false_det_003 | North Atlantic | 65.0 | -30.5 | 5 km | M1.6 | 2 | Ocean, far from stations |

**Distinguishing characteristics of false events:** Oceanic locations far from any seismic station, fewer than 4 associated phase picks, magnitudes below 2.0, automatic evaluation mode.

**Database tables:** `Event` (event records), `Origin` (location, time, evaluation mode), `Magnitude` (value, type), `OriginReference` (event-origin links), `Arrival` (pick-origin associations).

**CLI tools:** `scbulletin` (bulletin export), `scdb` (database operations).

**Output file:** `/home/ga/Desktop/verified_events.txt`

## Files

- `task.json` -- Task configuration (100 steps, 900s timeout, very_hard difficulty)
- `setup_task.sh` -- Ensures real event in DB, injects 3 false events via SeisComP API or SQL fallback, launches scolv and terminal
- `export_result.sh` -- Counts events, checks for false/real event presence, reads bulletin, and writes result JSON
- `verifier.py` -- Scores the result against the 4 criteria
