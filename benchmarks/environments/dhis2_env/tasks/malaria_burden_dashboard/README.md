# Task: malaria_burden_dashboard

## Overview

This task evaluates an AI agent's ability to use DHIS2 as a District Health Information Officer performing a multi-visualization malaria burden analysis for a provincial health management review.

**Difficulty**: Hard
**Timeout**: 720 seconds
**Max Steps**: 90

## Domain Context

In Sierra Leone's public health system, District Health Information Officers (DHIOs) are responsible for compiling, analyzing, and presenting health data to management teams. A key responsibility is producing analytical dashboards in DHIS2 for programme reviews. Malaria is Sierra Leone's highest-burden disease, and quarterly reviews require multi-dimensional analyses spanning monthly trends, positivity rates, and geographic distribution.

This task reflects the real quarterly workflow of a DHIO preparing for a provincial health management team meeting — a task that requires competence across DHIS2's Data Visualizer, Maps app, and Dashboard module simultaneously.

## Goal

Create a DHIS2 dashboard named **'Bo District Malaria Burden 2023'** containing three distinct visualization types showing malaria data for Bo district in 2023:

1. **Bar/Column Chart** — Monthly confirmed malaria cases (RDT positive or confirmed cases) for Bo district, full year 2023. Saved as favorite: `Bo Malaria Monthly Cases 2023`
2. **Pivot Table** — Quarterly malaria data (tested and/or positive counts) by quarter for Bo district 2023. Saved as favorite: `Bo Malaria Positivity Quarterly 2023`
3. **Thematic Map** — Malaria case distribution across Bo district facilities for 2023. Saved as map: `Bo Malaria Facility Map 2023`

All three must be added to the dashboard and the dashboard must be saved.

## What Makes This Hard

- The agent must independently discover which DHIS2 apps to use (Data Visualizer, Maps, Dashboard)
- Must identify the correct malaria-related data elements within DHIS2's extensive data catalog
- Must configure three distinct visualization types with correct dimensions (org unit, period, data element)
- Must navigate the two-step process: save visualization → add to dashboard
- No UI navigation path is provided — agent must explore the application

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| Dashboard created | 20 | Dashboard with name containing 'Malaria' or 'Bo' exists in DHIS2, created after task start |
| Dashboard has ≥2 items | 20 | Dashboard contains at least 2 visualization/map items |
| Dashboard has ≥3 items | 15 | Dashboard contains all 3 required items |
| Chart visualization saved | 15 | At least one COLUMN/BAR type visualization saved after task start |
| Map visualization saved | 15 | At least one MAP type saved after task start |
| Pivot table saved | 15 | At least one PIVOT_TABLE type visualization saved after task start |

**Pass threshold**: ≥60 points
**Mandatory**: Dashboard created (20 pts) must be satisfied to pass

## Verification Strategy

1. Query DHIS2 API for dashboards with names matching 'malaria'/'bo'/'burden' created after task start
2. Check dashboard item count via API
3. Query visualization and map tables for recently created items by type
4. Compare creation timestamps against task start time

## Data Reference

- **Target org unit**: Bo district (Sierra Leone DHIS2 demo)
- **Target period**: Year 2023 (monthly periods: 202301–202312)
- **Key data elements**: Malaria RDT tested, Malaria RDT positive (search DHIS2 maintenance for exact names)
- **DHIS2 apps to use**: Data Visualizer, Maps app, Dashboard app

## Edge Cases

- Agent may use different visualization names than specified — partial credit given if dashboard has correct item count
- Agent may not find a Map visualization — full score if 3 regular visualizations (chart + pivot + any) are created
- Sierra Leone demo data for 2023 may be sparse — agent should still complete the task structure even if data is empty
