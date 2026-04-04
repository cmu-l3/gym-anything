# Task: tb_programme_data_export

## Overview

This task evaluates an AI agent's ability to work across DHIS2's Tracker Capture module and Analytics module to extract TB programme data and create a programme monitoring visualization — reflecting the real workflow of a national disease programme data officer.

**Difficulty**: Hard
**Timeout**: 720 seconds
**Max Steps**: 90

## Domain Context

National TB Programme data officers in Sierra Leone are responsible for: (1) extracting individual patient-level data from DHIS2's Tracker module for cohort analysis, (2) producing aggregate visualizations for programme reviews, and (3) exporting data for external analysis. The TB programme in Sierra Leone has been a focus area since the country declared TB a public health emergency.

This task crosses two completely separate DHIS2 modules — Tracker Capture (individual patient data) and Data Visualizer (aggregate analytics) — requiring the agent to understand both the programme tracking and analytics layers of DHIS2.

## Goal

1. **Tracker Export**: In Tracker Capture or Capture app, find the TB programme, search for patients in Western Area Urban district, and export the working list to /home/ga/Downloads/

2. **Visualization**: Create a bar chart showing TB programme enrollments by month for Western Area Urban district for 2022. Save as favorite: `TB Notifications Western Area Urban 2022`

3. **Data Export**: Export the visualization data (CSV or Excel) to /home/ga/Downloads/

## What Makes This Hard

- Requires navigating TWO completely different DHIS2 modules (Tracker Capture + Data Visualizer)
- Agent must identify which programme is the "TB programme" from DHIS2's programme list
- Must configure the tracker search with correct org unit (Western Area Urban, not a facility)
- Finding the export function in Tracker Capture requires knowledge of the working list toolbar
- The visualization must be configured with correct dimensions (period type, org unit level, data element)
- Agent must save the visualization as a favorite before exporting data

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| At least 1 file in Downloads (newer than task start) | 25 | Any download was made |
| At least 2 files in Downloads (newer than task start) | 20 | Both tracker export and viz export present |
| Visualization created after task start | 25 | At least one new visualization saved in DHIS2 |
| Visualization name matches TB topic | 15 | Saved viz name contains 'TB', 'tuberculosis', or 'notifications' |
| TB tracked entity programme accessed | 15 | Evidence of TB programme tracker access |

**Pass threshold**: 60 points

## Verification Strategy

1. Check `/home/ga/Downloads/` for files modified after task start timestamp
2. Query DHIS2 API for visualizations created after task start
3. Check visualization names for TB-related keywords
4. Count downloaded files to distinguish between 1 and 2 exports

## Data Reference

- **TB Programme**: Available in DHIS2 Sierra Leone demo (search in Tracker Capture)
- **Target org unit**: Western Area Urban district (district-level org unit)
- **Target year**: 2022 (monthly periods: 202201-202212)
- **DHIS2 modules**: Tracker Capture/Capture app, Data Visualizer, potentially Reports

## Edge Cases

- The TB programme name in the demo may vary (e.g., "TB programme", "Tuberculosis Surveillance")
- The agent may export more than 2 files — verify at least 2 new downloads
- Some DHIS2 versions use "Capture" instead of "Tracker Capture" — both are acceptable
