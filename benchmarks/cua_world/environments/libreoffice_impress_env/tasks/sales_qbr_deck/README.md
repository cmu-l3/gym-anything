# Task: Sales QBR Deck (Q3 2023 Quarterly Business Review)

## Overview

**Occupation**: Sales Manager
**Difficulty**: very_hard
**Domain**: Retail Analytics / Sales Reporting
**Data Source**: US Census Bureau Monthly Retail Trade Survey, Q3 2023

## Background

Sales Managers routinely create Quarterly Business Review presentations to communicate performance results to leadership. A QBR synthesizes real business data into actionable insights with charts, trend analysis, and category breakdowns. This task tests the ability to build a data-driven multi-slide QBR from scratch using real Q3 2023 US retail sales data.

## Starting State

- **Draft file**: `/home/ga/Documents/Presentations/qbr_q3_2023.odp` — 2-slide minimal stub (title + agenda placeholder)
- **Data file**: `/home/ga/Documents/Presentations/q3_sales_data.csv` — US Census Bureau MRTS Q3 2023 retail sales by category (July–September 2023, billions USD)

## Goal / End State

The completed presentation at `/home/ga/Documents/Presentations/qbr_q3_2023.odp` must:
1. Contain **at least 7 slides** covering Q3 2023 retail performance
2. Have a **title slide** that clearly identifies this as a Q3 2023 Quarterly Business Review
3. Include **at least 2 charts** visualizing the retail sales data
4. Have **speaker notes with substantive content** on at least 3 slides
5. Be **exported as PDF** to `/home/ga/Documents/Presentations/qbr_q3_2023.pdf`

The task description deliberately does not specify which slides to create or how to navigate LibreOffice — the agent must determine the appropriate professional QBR structure.

## Success Criteria

| Criterion | Points | Threshold |
|-----------|--------|-----------|
| Slide count >= 7 | 25 | Required |
| Title identifies Q3 2023 + QBR/Quarterly Business Review | 20 | Required |
| Charts present >= 2 | 30 | Required |
| Speaker notes on >= 3 slides | 15 | Required |
| PDF export exists | 10 | Optional |
| **Pass threshold** | **65** | — |

## Verification Strategy

1. **ODP existence**: Fail immediately if file is missing or unreadable
2. **Slide count**: Count `<draw:page>` elements in content.xml
3. **Title check**: Regex search for "q3 2023"/"third quarter 2023" AND "quarterly business review"/"qbr" in first slide text
4. **Chart count**: Count `Object N/content.xml` entries containing `<chart:chart` in the ODP ZIP archive
5. **Notes**: Count `<presentation:notes>` elements with >25 non-tag characters of text
6. **PDF**: Copy file and check existence + size > 1KB

## Schema Reference

**q3_sales_data.csv columns**:
- `Category` — Retail category (NAICS-based)
- `July_2023_Billion_USD` — July 2023 sales estimate
- `August_2023_Billion_USD` — August 2023 sales estimate
- `September_2023_Billion_USD` — September 2023 sales estimate

## Edge Cases

- Agent may save file with different name — verifier checks specific path
- Charts inserted as images (screenshots) will NOT count — must be embedded OLE chart objects
- Speaker notes field must have text; placeholder text is filtered
