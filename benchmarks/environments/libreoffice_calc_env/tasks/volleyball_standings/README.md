# Volleyball League Standings Task

**Difficulty**: 🟡 Medium
**Skills**: Multi-step formulas, percentage calculation, data sorting with tiebreakers
**Duration**: 180 seconds
**Steps**: ~15

## Objective

Manage a recreational volleyball league standings table by calculating points based on league scoring rules (3 points per win, 1 point per loss), computing winning percentages, and sorting teams to determine playoff seeding order.

## Task Description

The agent must:
1. Open the volleyball standings spreadsheet (provided with team records)
2. Create formulas in column D (Points) using rule: Points = (Wins × 3) + (Losses × 1)
3. Copy the points formula to all 8 teams
4. Create formulas in column E (Win %) calculating: Win% = Wins / (Wins + Losses)
5. Copy the winning percentage formula to all 8 teams
6. Sort the complete data by Points (descending), with Win% as tiebreaker (descending)
7. Save the file

## Data Structure

| Team Name | Wins | Losses | Points | Win % |
|-----------|------|--------|--------|-------|
| Team...   | #    | #      | (calc) | (calc)|

## Expected Results

- **Column D (Points)**: Formula `=(B*3)+C` or equivalent in all team rows
- **Column E (Win%)**: Formula `=B/(B+C)` in all team rows
- **Sorted Order**: Teams ranked by points (highest first), ties broken by win percentage
- **Data Integrity**: Team names still aligned with their win/loss records

## Verification Criteria

1. ✅ **Points Formulas Present**: Cells D2-D9 contain formulas (not hard-coded values)
2. ✅ **Points Calculations Correct**: All point values match (Wins×3)+(Losses×1)
3. ✅ **Win% Formulas Present**: Cells E2-E9 contain division formulas
4. ✅ **Win% Calculations Correct**: All percentages match Wins/(Wins+Losses)
5. ✅ **Primary Sort Correct**: Teams ordered by Points descending
6. ✅ **Tiebreaker Sort Correct**: Teams with equal points ordered by Win% descending
7. ✅ **Data Integrity**: Team records remain properly aligned

**Pass Threshold**: 70% (5/7 criteria must pass)

## Skills Tested

- Formula creation with operators and parentheses
- Understanding non-standard scoring rules (not 1 point per win)
- Cell reference usage (relative references)
- Formula copying/fill-down
- Multi-column data range selection
- Sort dialog navigation with primary and secondary keys
- Data integrity during transformations

## Tips

- League scoring is NOT standard: Wins = 3pts, Losses = 1pt
- Use parentheses for clarity: `=(B2*3)+(C2*1)`
- Win% should be decimal between 0 and 1 (e.g., 0.625 for 5-3 record)
- Select entire data range (A1:E9) before sorting
- Set Sort Key 1 = Points (descending), Sort Key 2 = Win% (descending)
- Verify data alignment after sorting (team names match their records)