# Diagnose Station Anomaly via scrttv (`diagnose_station_anomaly_scrttv@1`)

## Task Overview

A duty seismologist investigates elevated false-alarm rates in a five-station GE-network monitoring system. The operator must visually inspect real-time waveforms in scrttv to identify which station is producing anomalous data (data gaps and noise spikes), disable that station's processing module bindings in scconfig to stop it from contaminating the automatic detection pipeline, and write a diagnostic report documenting findings and corrective action.

## Domain Context

**Occupation:** Geoscientists / Seismologists (SOC 19-2042.00)

Seismic monitoring networks rely on continuous data quality. A single malfunctioning station can inject spurious triggers into the automatic event detection pipeline, causing false alarms and degrading network reliability. Duty seismologists routinely inspect waveform displays to spot anomalous stations and must know how to isolate them operationally by removing their module bindings from the processing chain.

**Environment:** SeisComP seismological software suite with MariaDB database (`mysql -u sysop -psysop seiscomp`), configuration at `/home/ga/seiscomp/etc/`.

## Goal Description

1. Open scrttv (real-time trace viewer) and visually inspect waveform data from all five GE-network stations: TOLI, GSI, KWP, SANI, BKB.
2. Identify station GE.KWP as the source of anomalous data -- it exhibits noise spikes and data gaps compared to the clean traces of the other four stations.
3. Open scconfig and navigate to the Bindings panel. Remove the scautopick (and optionally scamp) module bindings for GE.KWP so it no longer feeds into automatic detection.
4. Write a diagnostic operator log to `/home/ga/Desktop/station_anomaly_report.txt` naming KWP as the faulty station, describing the observed symptoms, and documenting the corrective action taken.

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| KWP bindings removed | 35 | scautopick binding removed from `etc/key/station_GE_KWP` (25 pts); scamp binding also removed (10 pts) |
| Other stations preserved | 25 | All 4 non-target stations (TOLI, GSI, SANI, BKB) retain their scautopick bindings with no collateral damage |
| Report identifies KWP | 25 | Report file exists at the correct path, is at least 20 bytes, and names KWP as the problematic station |
| Report quality | 15 | Report describes both the observed symptoms (noise, gaps, spikes) and the corrective action taken (disabled, removed) |

**Pass threshold:** 60 / 100

## Verification Strategy

The post-task `export_result.sh` script inspects the filesystem and report content:

- Checks whether `$SEISCOMP_ROOT/etc/key/station_GE_KWP` still contains `scautopick` and `scamp` lines.
- Counts how many of the 4 other station key files still contain scautopick bindings (expected: 4).
- Detects if any non-target station was incorrectly disabled (wrong-station penalty).
- Reads `/home/ga/Desktop/station_anomaly_report.txt` and checks for KWP mention, symptom keywords (noise, gap, spike, anomaly, corrupt, etc.), and action keywords (disabled, removed, deactivated, excluded, etc.).
- A do-nothing guard returns score 0 if KWP still has all bindings and no report exists.

The `verifier.py::verify_diagnose_station_anomaly_scrttv` function consumes the exported JSON and computes the weighted score.

## Schema and Data Reference

**Station key files:** `$SEISCOMP_ROOT/etc/key/station_GE_{STATION}` -- each contains module names (one per line) such as `scautopick` and `scamp`.

**SDS waveform archive:** `$SEISCOMP_ROOT/var/lib/archive/2024/GE/{STATION}/BHZ.D/` -- miniSEED files for day 2024-001. KWP data has corrupted records (zeroed data sections and random noise bytes injected every 3rd record).

**Stations:** GE.TOLI, GE.GSI, GE.KWP (target), GE.SANI, GE.BKB

**Report output:** `/home/ga/Desktop/station_anomaly_report.txt`

## Files

- `task.json` -- Task configuration (100 steps, 900s timeout, very_hard difficulty)
- `setup_task.sh` -- Injects anomalous KWP waveforms, sets up bindings for all 5 stations, launches scrttv
- `export_result.sh` -- Extracts binding state, report content, and writes result JSON
- `verifier.py` -- Scores the result against the 4 criteria
