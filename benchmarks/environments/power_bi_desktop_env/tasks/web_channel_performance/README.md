# Task: web_channel_performance

## Overview

A search marketing strategist must deliver a monthly channel performance report to a client. The raw web analytics CSV has a typical real-world data quality issue: numeric columns (Revenue, Sessions, Users) contain comma-formatted thousands (e.g., "126,870") stored as text, and Bounce Rate is stored as a percentage string ("71.59%"). These must be fixed in Power Query before any analysis. The task then requires creating a time-series line chart showing each year's revenue trajectory, a ranked source table, a KPI card, and a year slicer — four distinct visual types with correct field configuration.

## Data

- **Source**: `C:\Users\Docker\Desktop\PowerBITasks\website_analytics.csv` (249 rows)
- **Columns**: Source / Medium, Year, Month of the year, Users, New Users, Sessions, Bounce Rate, Pageviews, Avg. Session Duration, Conversion Rate (%), Transactions, Revenue, Quantity Sold
- **Data types issue**: Revenue = "83,244" (string), Bounce Rate = "71.59%" (string), Sessions = "194,667" (string)
- **Years**: 2019, 2020
- **Source/Medium values**: labeled A through several letters (anonymized channel names)

## Goal

Build and save `Channel_Performance.pbix` on the Desktop.

**Power Query transformations**:
- Convert Revenue column to numeric (remove commas)
- Convert Sessions column to numeric (remove commas)
- Convert Bounce Rate to decimal (remove '%' sign, divide by 100 or treat as-is)

**DAX measure**:
- `Revenue_Per_Session = DIVIDE(SUM([Revenue]), SUM([Sessions]), 0)`

**Four required visuals on one page**:
1. Line Chart: Revenue (Y) by Month of the year (X), Year as legend
2. Table: Source / Medium rows sorted by Revenue descending
3. Card: Revenue_Per_Session measure
4. Slicer: Year column

**Output**: `C:\Users\Docker\Desktop\Channel_Performance.pbix`

## Starting State

- Power BI Desktop is open, blank canvas
- `website_analytics.csv` available in `C:\Users\Docker\Desktop\PowerBITasks\`
- No prior `Channel_Performance.pbix` exists

## Agent Workflow

1. Import `website_analytics.csv`
2. In Power Query Editor, convert Revenue and Sessions from text to numeric
3. Convert Bounce Rate from percentage string to decimal
4. Close and apply Power Query changes
5. Create `Revenue_Per_Session` DAX measure
6. Build Line Chart with correct Month/Year/Revenue fields
7. Build Table sorted by Revenue descending
8. Add Card for Revenue_Per_Session
9. Add Year Slicer
10. Save as `Channel_Performance.pbix`

No navigation steps are provided — the agent must independently navigate Power Query Editor and configure all visuals.

## Success Criteria (100 points total)

| Criterion | Points | What is checked |
|-----------|--------|-----------------|
| File saved | 15 | `Channel_Performance.pbix` exists on Desktop |
| Power Query type conversion | 20 | DataMashup M code has number-conversion steps |
| Revenue_Per_Session measure | 25 | Measure name appears in data model or layout |
| Line chart present | 20 | lineChart visual type in report layout |
| Table + Card + Slicer | 20 | All three supporting visual types present |

**Pass threshold**: 70 points

## Verification Strategy

1. `export_result.ps1` closes PBI, unzips `.pbix`, reads `Report/Layout` and `DataMashup`
2. Checks DataMashup M code for type-conversion patterns (Table.TransformColumnTypes, Number.From, Text.Replace)
3. Checks DataModel binary and layout for `Revenue_Per_Session`
4. Counts visual types
5. Writes `channel_performance_result.json`

## Anti-Gaming Measures

- Baseline confirms no pre-existing `.pbix`
- DataMashup type-conversion check is non-trivial (can't pass with blank report)
- Measure check requires specific string in data model
