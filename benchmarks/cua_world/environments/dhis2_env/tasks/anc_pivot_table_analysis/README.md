# Task: anc_pivot_table_analysis

## Overview

This task evaluates an AI agent's ability to use DHIS2's Analytics module to perform a multi-dimensional ANC coverage analysis — a core workflow for Monitoring & Evaluation analysts in reproductive health programmes.

**Difficulty**: Hard
**Timeout**: 720 seconds
**Max Steps**: 90

## Domain Context

In Sierra Leone, ANC (Antenatal Care) coverage is a key maternal health indicator. The national target is that ANC 1st visit coverage should be ≥80% and ANC 4th visit coverage (completing the recommended minimum visits) should approach ANC 1st visit numbers. M&E analysts routinely produce these pivot tables in DHIS2 for quarterly and annual programme reviews.

This task tests three distinct skills: (1) multi-dimensional pivot table configuration in DHIS2 Analytics, (2) data export for external use, and (3) data interpretation and documentation — requiring both technical DHIS2 skills and domain knowledge about maternal health indicators.

## Goal

1. **Pivot Table**: Create a pivot table showing ANC 1st and ANC 4th visit data by district and quarter for 2023. Save as: `National ANC Coverage Districts 2023`

2. **Export**: Export the pivot table data to /home/ga/Downloads/ (Excel or CSV)

3. **Analysis Notes**: Create /home/ga/Desktop/anc_analysis_notes.txt documenting which districts had ANC 4th visit < 50% of ANC 1st visit, plus overall coverage assessment

## What Makes This Hard

- Multi-dimensional pivot table configuration: data element (2 elements), period (quarterly), org unit level (district) must all be configured
- Must navigate from the analytics module to the correct data elements (ANC indicators not immediately obvious)
- Must save as a "favorite" — a step separate from running the analysis
- Requires data interpretation: agent must read and understand the numbers to identify low-coverage districts
- Must produce a structured text analysis — requires judgment beyond mechanical task execution
- Three independent subtasks that must all be completed

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| Visualization/favorite created after task start | 25 | At least one new pivot table or visualization saved |
| Favorite has ANC-related name | 15 | Name contains 'ANC', 'antenatal', or 'coverage' |
| Export file in Downloads (newer than task start) | 25 | CSV, XLSX, or XLS file exported |
| Analysis text file created | 20 | /home/ga/Desktop/anc_analysis_notes.txt exists |
| Text file has substantive content (>100 chars) | 15 | File contains analysis, not just a title |

**Pass threshold**: 60 points

## Verification Strategy

1. Query DHIS2 API for visualizations created after task start with ANC-related names
2. Check /home/ga/Downloads/ for new files after task start
3. Check /home/ga/Desktop/anc_analysis_notes.txt existence and content

## Data Reference

- **Key data elements**: "ANC 1st visit" and "ANC 4th visit" (search DHIS2 maintenance/analytics)
- **Period**: 2023 quarterly (Q1-Q4 2023)
- **Org unit level**: District level across Sierra Leone (14 districts)
- **DHIS2 module**: Analytics → Data Visualizer (Pivot Table type) or Reports → Analytics Tables

## Edge Cases

- Agent may use "indicators" instead of "data elements" — either is valid if they reference the same ANC metric
- DHIS2 may show the analysis as "PIVOT_TABLE" or "TABLE" type in the API
- The text file content should mention at least one district name to demonstrate genuine data reading
