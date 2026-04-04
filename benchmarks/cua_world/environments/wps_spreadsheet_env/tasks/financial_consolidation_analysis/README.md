# Financial Consolidation Analysis

## Occupation
Accountants and Auditors

## Industry
Professional, Scientific, and Technical Services

## Difficulty
very_hard

## Description
Multi-subsidiary financial consolidation for Meridian Holdings with three subsidiaries (Alpha Inc, Beta Corp, Gamma LLC). Agent must create consolidated financial statements with intercompany elimination entries, compute financial ratios, perform year-over-year variance analysis with conditional formatting, and build a dashboard chart.

## Data Source
Financial statement data based on real SEC EDGAR filing patterns for mid-cap holding companies. Trial balance structure follows US GAAP conventions.

## Features Exercised
- Multi-sheet cross-references (consolidation formulas referencing 3 subsidiary sheets)
- Intercompany elimination formulas (revenue, COGS, operating expense, AR/AP adjustments)
- Financial ratio formulas (Current, Quick, D/E, margins, ROE, ROA)
- Conditional formatting (red/green for material variances)
- Grouped bar chart (current vs prior year comparison)

## Verification Criteria (6 criteria, 100 points)
1. Consolidated sheet exists with correct structure (15 pts)
2. Consolidated values correct with IC eliminations applied (20 pts)
3. Financial Ratios sheet with 8 ratios referencing consolidated data (20 pts)
4. Variance Analysis sheet with dollar and % variance (15 pts)
5. Conditional formatting on variance percentages (15 pts)
6. Dashboard chart comparing current vs prior year (15 pts)

## Do-Nothing Score
0 - Starter workbook has only 5 data sheets; verifier checks for new sheets with formulas, conditional formatting, and charts.
