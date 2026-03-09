# Configure Playback Processing Pipeline (`configure_playback_processing_pipeline@1`)

## Task Overview

A seismologist configures an offline processing pipeline (scautopick + scautoloc) to retroactively detect the 2024 Noto Peninsula M7.5 earthquake from archived waveform data. The task requires setting station bindings, configuring bandpass filter parameters, executing a playback of day 2024-001 waveforms, and verifying that the pipeline produces automatic picks and origins in the database.

## Domain Context

**Occupation:** Geoscientists / Seismologists (SOC 19-2042.00)

When the real-time processing chain is offline during a significant seismic event, observatories must run offline playback to retroactively generate detections. This involves configuring the same modules (scautopick for phase picking, scautoloc for event association and location) that would normally run in real time, but feeding them archived waveform data from the SeisComP SDS archive. Proper filter selection (e.g., Butterworth bandpass) is critical for teleseismic P-wave detection.

**Environment:** SeisComP with MariaDB database (`mysql -u sysop -psysop seiscomp`), configuration at `/home/ga/seiscomp/etc/`.

## Goal Description

1. Open scconfig and navigate to the Bindings panel. Configure scautopick module bindings for all three target stations: GE.GSI, GE.BKB, GE.SANI.
2. Configure scautopick with an appropriate bandpass filter setting -- recommended `BW(3,1.5,15)` for teleseismic P-wave detection -- by creating or editing `$SEISCOMP_ROOT/etc/scautopick.cfg`.
3. Configure scautoloc to run with the default velocity model and a minimum pick count of 3.
4. Run a SeisComP playback of the archived waveform data for day 2024-001 through the processing chain.
5. Verify that at least one automatic P-phase pick per station and at least one automatic origin were generated in the database.
6. Export a summary to `/home/ga/Desktop/playback_results.txt` listing the number of automatic picks and origins found.

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| Station bindings | 25 | scautopick bindings configured for all 3 target stations (GE.GSI, GE.BKB, GE.SANI) |
| scautopick filter | 25 | `scautopick.cfg` exists and contains a Butterworth bandpass filter (BW) setting |
| Picks generated | 25 | At least 1 automatic pick per station (3 total), confirmed via database query |
| Origins generated | 15 | At least 1 automatic origin detected in database by scautoloc |
| Results file | 10 | Summary file at `/home/ga/Desktop/playback_results.txt` mentions both pick counts and origin counts |

**Pass threshold:** 60 / 100

## Verification Strategy

The post-task `export_result.sh` script queries the system state:

- Counts station key files containing `scautopick` for the 3 target stations.
- Checks for existence of `$SEISCOMP_ROOT/etc/scautopick.cfg` and extracts any filter string.
- Queries the MariaDB database for automatic picks (`SELECT COUNT(*) FROM Pick WHERE evaluationMode='automatic'`) and per-station pick counts.
- Queries for automatic origins (`SELECT COUNT(*) FROM Origin WHERE evaluationMode='automatic'`).
- Checks the results summary file for pick/origin keywords.
- A do-nothing guard returns score 0 if no bindings, no config, and no picks exist.

The `verifier.py::verify_configure_playback_processing_pipeline` function consumes the exported JSON and computes the weighted score.

## Schema and Data Reference

**Station key files:** `$SEISCOMP_ROOT/etc/key/station_GE_{STATION}` -- setup clears all bindings; agent must add `scautopick` lines.

**Module config:** `$SEISCOMP_ROOT/etc/scautopick.cfg` -- agent should set `picker.BW` or `filter` parameter with value like `BW(3,1.5,15)`.

**SDS waveform archive:** `$SEISCOMP_ROOT/var/lib/archive/2024/GE/{STATION}/BHZ.D/` -- miniSEED files for day 2024-001 from three GE stations.

**Database tables:** `Pick` (automatic picks), `Origin` (automatic origins), `Arrival` (pick-origin associations).

**Output file:** `/home/ga/Desktop/playback_results.txt`

## Files

- `task.json` -- Task configuration (100 steps, 900s timeout, very_hard difficulty)
- `setup_task.sh` -- Clears all bindings and module configs, verifies SDS data, launches scconfig and terminal
- `export_result.sh` -- Extracts binding state, config, database counts, and writes result JSON
- `verifier.py` -- Scores the result against the 5 criteria
