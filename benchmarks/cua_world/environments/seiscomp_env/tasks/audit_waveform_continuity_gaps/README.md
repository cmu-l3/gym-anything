# Audit Waveform Continuity and Report Gaps (`audit_waveform_continuity_gaps@1`)

## Overview
This task evaluates the agent's ability to assess seismic data quality by detecting time gaps in continuous waveform files. The agent must analyze the SeisComP SDS archive, identify stations with missing data (gaps larger than 3 seconds), and generate a structured CSV report. This requires understanding miniSEED time structures and using command-line tools or scripting to identify discontinuities.

## Rationale
**Why this task is valuable:**
- **Data Quality Control**: Continuous waveforms are critical for earthquake monitoring; gaps can cause missed events.
- **Archive Management**: Verifies the integrity of the data stored in the SDS (SeisComP Data Structure).
- **Scripting/Analysis**: Requires parsing binary data headers (via tools or python) to calculate time differences between records.
- **Real-world Context**: Network operators run gap analysis daily to catch telemetry outages or station downtime.

**Real-world Context:** A network operator at the GEOFON data center notices the event detection system missed a small earthquake. They suspect data transmission dropouts (gaps) on key stations. You are tasked with scanning the day's archive to pinpoint exactly when and where data gaps occurred.

## Task Description

**Goal:** Analyze the SDS waveform archive for **January 1, 2024 (Day 001)**, detect all time gaps larger than **3.0 seconds** across all provided stations, and save the results to a CSV file.

**Starting State:**
- SeisComP is installed and the SDS archive at `/home/ga/seiscomp/var/lib/archive` is populated with miniSEED data.
- Most data is continuous, but **specific stations have had artificial gaps introduced** (simulating outages).
- System tools `scart` (SeisComP Archive Tool) and Python 3 are available.

**Expected Actions:**
1. Navigate to the SDS archive (`/home/ga/seiscomp/var/lib/archive`) or use `scart` to inspect the data.
2. Develop a method (using Python scripting or parsing `scart` output) to iterate through the miniSEED files for Year 2024, Day 001.
3. For each file, determine if there are jumps in time between consecutive records that exceed 3.0 seconds.
4. Generate a report file `~/gap_report.csv` with the following header and columns:
   `Network,Station,Channel,GapStart,GapDuration`
5. If no gaps are found for a file, do not include it.

**Final State:**
- A valid CSV file `~/gap_report.csv` exists containing the identified gaps matching the introduced artifacts.

## Verification Strategy

### Primary Verification: CSV Content Analysis
The verifier compares the agent's `gap_report.csv` against the ground truth of introduced gaps (known timestamps and durations).

1. **File Existence**: Checks if `~/gap_report.csv` exists and was created during the task.
2. **Format Check**: Verifies CSV headers and column count.
3. **Gap Accuracy**: Checks if rows match the introduced gaps (TOLI at ~07:10 for 10s, GSI at ~07:12 for 45s).
4. **False Positives**: Penalizes reporting gaps where none exist.

### Secondary Verification: Trajectory VLM Check
- Evaluates the sequence of agent actions to ensure a script was actually written or tools were genuinely used to parse the miniSEED files (anti-gaming).