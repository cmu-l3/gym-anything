# Task: hr_workforce_analytics

## Overview

An HR analytics manager is preparing a workforce quality report for executive review. The raw employee data has incomplete `Performance Score` records — a realistic data quality issue that must be addressed in Power Query before any analysis can begin. This task chains four distinct Power BI skills: Power Query data transformation (null filtering + conditional column), page naming, three different visual types (Stacked Bar, Line, Slicer), and proper field assignment.

## Data

- **Source**: `C:\Users\Docker\Desktop\PowerBITasks\employee_performance.csv` (1000 rows)
- **Columns**: ID, Name, Age, Gender, Department, Salary, Joining Date, Performance Score, Experience, Status, Location, Session
- **Key data issue**: Multiple rows have blank/null `Performance Score` (rows 3, 7, 8, 9 in sample — at least 150+ blank values in full dataset)
- **Departments**: HR, Sales, IT (and others)
- **Status values**: Active, Inactive

## Goal

Build and save `HR_Workforce_Analytics.pbix` on the Desktop with:

**Power Query transformations (two steps)**:
1. Filter out rows where `Performance Score` is null/blank
2. Add a conditional column `Performance_Tier`: "High" if score > 3, "Mid" if score 2–3, "Low" if score < 2

**Report structure**:
- Single page named exactly **"Workforce Analysis"**
- Stacked Bar Chart: employee count by Department, colored by Performance_Tier
- Line Chart: average Salary by Experience (years)
- Slicer for Status (Active / Inactive)

## Starting State

- Power BI Desktop is open with a blank canvas
- `employee_performance.csv` is in `C:\Users\Docker\Desktop\PowerBITasks\`
- No prior `HR_Workforce_Analytics.pbix` exists

## Agent Workflow

1. Import `employee_performance.csv` into Power BI
2. Open Power Query Editor
3. Filter out rows with null Performance Score
4. Add conditional column `Performance_Tier` based on score ranges
5. Close and apply Power Query changes
6. Rename the default report page to "Workforce Analysis"
7. Build Stacked Bar Chart: Department + Performance_Tier breakdown
8. Build Line Chart: Salary by Experience
9. Add Slicer for Status
10. Save as `HR_Workforce_Analytics.pbix`

No UI steps are given — the agent must navigate Power Query Editor, the field pane, and page tab controls independently.

## Success Criteria (100 points total)

| Criterion | Points | What is checked |
|-----------|--------|-----------------|
| File saved | 15 | `HR_Workforce_Analytics.pbix` exists on Desktop |
| Page named correctly | 20 | Page name "Workforce Analysis" in Report/Layout |
| Power Query transformation | 20 | DataMashup M code has null-filter or conditional column step |
| Performance_Tier column | 20 | "Performance_Tier" in DataMashup or layout text |
| Required visual types | 25 | stackedBarChart (or barChart), lineChart, and slicer all present |

**Pass threshold**: 70 points

## Verification Strategy

1. `export_result.ps1` closes PBI, unzips `.pbix`, parses `Report/Layout` for page names and visual types, reads `DataMashup` ZIP for M code content, outputs `hr_workforce_result.json`
2. `verifier.py` copies result JSON and scores each criterion

## Anti-Gaming Measures

- Baseline confirms no pre-existing target file
- Start timestamp compared against file modification time
- DataMashup M code check cannot be satisfied by just saving a blank report
- Page name exact match (case-insensitive)
