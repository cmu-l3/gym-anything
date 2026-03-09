# Production Capacity Planning

## Occupation
First-Line Supervisors of Production and Operating Workers

## Industry
Manufacturing

## Difficulty
very_hard

## Description
Production scheduling and capacity planning for a manufacturing facility with 4 production lines and 15 customer orders. Agent must allocate orders to compatible lines, calculate production dates respecting a working-day calendar, compute weekly utilization rates, perform revenue/cost analysis, and create visualizations.

## Data Source
Production planning data based on real manufacturing facility metrics, capacity constraints, and order patterns typical of discrete manufacturing operations.

## Features Exercised
- Date calculations (WORKDAY, NETWORKDAYS, production day computation)
- SUMPRODUCT/COUNTIFS for utilization calculations
- Conditional formatting with 3-tier color coding (red/yellow/green)
- Stacked bar chart for utilization visualization
- Multi-sheet cross-references (Schedule -> Utilization, Orders -> Revenue)

## Verification Criteria (6 criteria, 100 points)
1. Schedule sheet with order allocations (20 pts)
2. Date calculations and slack computation (20 pts)
3. Utilization sheet with weekly percentages (20 pts)
4. Conditional formatting on utilization (15 pts)
5. Revenue/cost analysis with margin (15 pts)
6. Stacked bar chart (10 pts)

## Do-Nothing Score
0 - Starter workbook has only 3 data sheets; verifier checks for new sheets.
