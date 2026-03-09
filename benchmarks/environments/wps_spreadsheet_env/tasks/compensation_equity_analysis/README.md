# Compensation Equity Analysis

## Occupation
Human Resources Managers

## Industry
Management of Companies and Enterprises

## Difficulty
very_hard

## Description
Annual pay equity review for 36 employees across 6 departments. Agent must calculate compa-ratios using INDEX-MATCH against market benchmarks, perform statistical analysis by gender and ethnicity, flag outlier employees needing salary adjustments, apply tiered conditional formatting, and create a scatter chart of tenure vs compa-ratio.

## Data Source
Employee compensation data modeled on real BLS Occupational Employment and Wage Statistics (OEWS) with market salary benchmarks from published industry compensation surveys (Radford, Mercer, Towers Watson).

## Features Exercised
- INDEX-MATCH or VLOOKUP across sheets (employee data -> market benchmarks)
- Statistical formulas (AVERAGE, MEDIAN, STDEV, COUNTIFS, AVERAGEIFS)
- Conditional formatting with multiple tiers (red/yellow/green)
- Scatter chart with multiple series (male vs female)
- Date-based tenure calculations (DATEDIF or YEARFRAC)

## Verification Criteria (6 criteria, 100 points)
1. Compa_Ratio sheet with lookup formulas (25 pts)
2. Equity_Summary with gender/ethnicity statistical breakdowns (20 pts)
3. Flagged_Employees with dollar adjustment calculations (15 pts)
4. Conditional formatting on compa-ratio values (15 pts)
5. Scatter chart tenure vs compa-ratio (15 pts)
6. Cross-sheet formula references (10 pts)

## Do-Nothing Score
0 - Starter workbook has only 2 data sheets; verifier checks for 4 new analysis sheets.
