# Task: ESG Sustainability Report Presentation

## Overview

**Occupation**: Sustainability Specialists
**Difficulty**: very_hard
**Domain**: Corporate Sustainability / ESG Reporting
**Data Source**: Apple Inc. Environmental Progress Report 2023 (real published figures)

## Background

Sustainability Specialists create annual ESG reports to communicate environmental, social, and governance performance to investors, regulators, and the public. This task tests the ability to build a complete, multi-section ESG presentation from a minimal draft using real sustainability metrics data.

## Starting State

- **Draft file**: `/home/ga/Documents/Presentations/esg_report_2022.odp` — 4-slide stub (title, KPI overview, environmental placeholder, goals)
- **Data file**: `/home/ga/Documents/Presentations/esg_metrics_2022.csv` — Real FY2022 ESG metrics (emissions, energy, water, waste, workforce diversity, governance)

## Goal / End State

The completed presentation at `/home/ga/Documents/Presentations/esg_report_2022.odp` must:
1. Contain **at least 10 slides** covering environmental, social, and governance sections
2. Include **at least 3 embedded data charts** visualizing ESG trends from the CSV data
3. Have **speaker notes with content on at least 6 slides**
4. Have **consistent slide transitions on at least 8 slides**
5. Be **exported as PDF** to `/home/ga/Documents/Presentations/esg_report_2022.pdf`

## Success Criteria

| Criterion | Points | Threshold |
|-----------|--------|-----------|
| Slide count >= 10 | 25 | Required |
| Charts >= 3 | 30 | Required |
| Speaker notes on >= 6 slides | 20 | Required |
| Transitions on >= 8 slides | 15 | Required |
| PDF export exists | 10 | Optional |
| **Pass threshold** | **65** | — |

## Verification Strategy

1. **ODP existence**: Fail immediately if file missing
2. **Slide count**: Count `<draw:page>` elements in content.xml
3. **Charts**: Count `Object N/content.xml` files in ZIP containing `chart:chart`
4. **Notes**: Count `<presentation:notes>` elements with >25 non-tag chars
5. **Transitions**: Count slides with `presentation:transition-style=` or `<presentation:transition>`
6. **PDF**: Copy and verify existence + size > 1KB

## ESG Data Reference

The `esg_metrics_2022.csv` file contains real Apple Inc. ESG data (2020-2022) covering:
- **Environmental**: Carbon emissions (Scope 1+2+3), Electricity use, Water, Waste diversion
- **Social**: Workforce diversity (women, underrepresented groups), Supplier audits, Pay equity
- **Governance**: Board independence, Ethics programs

## Edge Cases

- Charts inserted as screenshots/images do NOT count — must be OLE embedded charts
- Partial credit awarded for meeting some but not all criteria
