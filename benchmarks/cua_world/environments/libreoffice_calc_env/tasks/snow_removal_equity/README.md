# Neighborhood Snow Removal Equity Tracker Task

**Difficulty**: 🟡 Medium  
**Skills**: COUNTIF formulas, mathematical operations, conditional logic, equity analysis  
**Duration**: 180 seconds  
**Steps**: ~12

## Objective

Analyze a neighborhood snow removal tracking spreadsheet to identify unfair work distribution and calculate adjusted assignments to restore equity. This task tests formula creation (COUNTIF, division, subtraction, IF/ABS), multi-sheet navigation, and understanding of fairness algorithms commonly used in community management.

## Task Description

It's mid-February, and tensions are high in your neighborhood. Some residents have been shoveling the shared walkway every time it snows, while others haven't done it once. The neighborhood association needs to calculate "makeup" shifts for under-contributors to restore fairness.

The agent must:
1. Open a partially completed tracking spreadsheet with two sheets
2. **Sheet 1 "Snow Events"**: Contains 18 logged snow dates and who shoveled (already filled)
3. **Sheet 2 "Household Summary"**: Contains household names but empty calculation columns
4. Create COUNTIF formulas to count each household's contributions
5. Calculate fair share per household (total events ÷ number of households)
6. Calculate deficit/surplus for each household (actual - fair share)
7. Calculate makeup shifts needed (only for under-contributors)
8. Add totals row for validation
9. Save the file

## Data Structure

**Sheet 1: "Snow Events"** (18 events, pre-filled)
- Columns: Date | Day | Who Shoveled
- Data spans December 2024 through February 2025
- 6 households: Johnson, Smith, Patel, Lee, Garcia, O'Brien

**Sheet 2: "Household Summary"** (template to complete)
- Column A: Household (6 names pre-filled)
- Column B: Times Shoveled (EMPTY - needs COUNTIF formula)
- Column C: Fair Share (EMPTY - needs calculation)
- Column D: Deficit/Surplus (EMPTY - needs calculation)
- Column E: Makeup Shifts Needed (EMPTY - needs conditional formula)

## Expected Results

Based on the seeded data:
- **Johnson**: 6 times (surplus +3, makeup = 0)
- **Smith**: 5 times (surplus +2, makeup = 0)
- **Patel**: 4 times (surplus +1, makeup = 0)
- **Lee**: 2 times (deficit -1, makeup = 1)
- **Garcia**: 1 time (deficit -2, makeup = 2)
- **O'Brien**: 0 times (deficit -3, makeup = 3)
- **Fair Share**: 3 per household (18 ÷ 6)
- **Total makeup shifts**: 6

## Required Formulas

1. **Column B (Times Shoveled)**: `=COUNTIF('Snow Events'.C:C, A2)`
2. **Column C (Fair Share)**: `=18/6` or `=(COUNTA('Snow Events'.A:A)-1)/6`
3. **Column D (Deficit/Surplus)**: `=B2-C2`
4. **Column E (Makeup Shifts)**: `=IF(D2<0, ABS(D2), 0)` or `=MAX(0, -D2)`

## Verification Criteria

1. ✅ **COUNTIF Formulas Present**: Column B uses COUNTIF referencing Snow Events sheet
2. ✅ **Counts Accurate**: Each household's count matches actual occurrences (Johnson=6, Smith=5, etc.)
3. ✅ **Fair Share Correct**: All households show fair share of 3
4. ✅ **Deficits Calculated**: Column D correctly shows actual minus fair share
5. ✅ **Makeup Properly Assigned**: Only negative deficits show positive makeup values
6. ✅ **Conservation Law**: Total surplus equals total deficit (sum of column D = 0)
7. ✅ **Total Validation**: Sum of contributions equals 18

**Pass Threshold**: 85% (requires 6 out of 7 criteria)

## Skills Tested

- Multi-sheet workbook navigation
- COUNTIF function for occurrence counting
- Cross-sheet cell references
- Division and subtraction operations
- Conditional logic (IF statements)
- Absolute value function (ABS)
- Data validation and totals
- Understanding of equity vs. equality

## Real-World Context

This scenario represents actual community management challenges where shared responsibilities need equitable distribution. The same approach applies to:
- Rotating chores in shared housing
- Community garden maintenance schedules
- Carpool coordination
- HOA duty assignments
- Team project contribution tracking

## Tips

- Use sheet name references in formulas: `'Snow Events'.C:C`
- COUNTIF syntax: `=COUNTIF(range, criteria)`
- The chain link icon in column headers controls whether width/height changes are linked
- Use Ctrl+Home to return to cell A1
- Formulas starting with `=` are automatically recognized
- Negative deficits indicate under-contribution; positive indicates over-contribution