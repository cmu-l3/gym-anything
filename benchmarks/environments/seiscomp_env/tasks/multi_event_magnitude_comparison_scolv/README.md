# Multi-Event Magnitude Comparison via scolv (`multi_event_magnitude_comparison_scolv@1`)

## Task Overview

A seismologist imports an M6.2 aftershock event from a QuakeML file into a SeisComP database that already contains the 2024 Noto Peninsula M7.5 mainshock. After import, the operator must verify both events in scolv, set the aftershock's event type to "earthquake" and its preferred magnitude type to "Mw(mB)", and export a formatted comparison bulletin containing both events.

## Domain Context

**Occupation:** Geoscientists / Seismologists (SOC 19-2042.00)

After a major earthquake, seismologists must incorporate aftershock data from external sources (e.g., USGS QuakeML feeds) into their local monitoring database for unified analysis. This involves format conversion (QuakeML to SeisComP XML), database import, event type classification, magnitude type selection, and bulletin generation. The ability to manage multiple events side-by-side and produce standardized bulletins is a core operational skill.

**Environment:** SeisComP with MariaDB database (`mysql -u sysop -psysop seiscomp`), configuration at `/home/ga/seiscomp/etc/`.

## Goal Description

1. Convert the aftershock QuakeML file at `/home/ga/Desktop/aftershock_data.xml` to SeisComP XML format using the `convert_quakeml.py` script or equivalent tool.
2. Import the converted event into the SeisComP database using `scdb` with the MySQL database plugin.
3. Open scolv and verify that both the M7.5 mainshock and the M6.2 aftershock appear in the event list.
4. In scolv, select the aftershock event and set its event type to "earthquake" and its preferred magnitude type to "Mw(mB)".
5. Export a formatted event bulletin to `/home/ga/Desktop/event_comparison.txt` using `scbulletin`, containing both the mainshock and aftershock with their magnitudes and locations.

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| Aftershock imported | 30 | Aftershock event exists in database and event count has increased from baseline |
| Event type correct | 20 | Aftershock event type set to "earthquake" in the database |
| Magnitude type correct | 20 | Aftershock preferred magnitude type set to "Mw(mB)" |
| Bulletin with both events | 30 | Bulletin file at `/home/ga/Desktop/event_comparison.txt` contains identifiable data for both the mainshock and aftershock |

**Pass threshold:** 60 / 100

## Verification Strategy

The post-task `export_result.sh` script queries the database and filesystem:

- Counts events in the Event table and compares to the pre-task baseline count stored in `/tmp/`.
- Checks for an origin near lat ~37.31, lon ~136.79 (aftershock location) in the Origin table.
- Reads the aftershock's event type from the Event table.
- Reads the aftershock's preferred magnitude type from the Magnitude table.
- Checks the bulletin file for references to both events (mainshock identified by M7.5 / lat ~37.5, aftershock by M6.2 / lat ~37.3).
- A do-nothing guard returns score 0 if aftershock is not imported and no bulletin exists.

The `verifier.py::verify_multi_event_magnitude_comparison_scolv` function consumes the exported JSON and computes the weighted score.

## Schema and Data Reference

**Aftershock QuakeML:** `/home/ga/Desktop/aftershock_data.xml` -- USGS QuakeML for event us6000m13n (M6.2, 2024-01-01T07:34:56Z, Noto Peninsula aftershock, lat 37.3107, lon 136.7858, depth 10 km).

**Mainshock:** Already in database -- us6000m0xl (M7.5, 2024-01-01, Noto Peninsula, lat ~37.5, lon ~137.3).

**Database tables:** `Event` (event type, preferred origin/magnitude IDs), `Origin` (location, time), `Magnitude` (value, type).

**CLI tools:** `convert_quakeml.py` (at `/workspace/scripts/`), `scdb` (database import), `scbulletin` (bulletin export).

**Output file:** `/home/ga/Desktop/event_comparison.txt`

## Files

- `task.json` -- Task configuration (100 steps, 900s timeout, very_hard difficulty)
- `setup_task.sh` -- Ensures mainshock in DB, cleans previous aftershock, creates QuakeML file on Desktop, launches scolv and terminal
- `export_result.sh` -- Extracts event counts, aftershock attributes, bulletin content, and writes result JSON
- `verifier.py` -- Scores the result against the 4 criteria
