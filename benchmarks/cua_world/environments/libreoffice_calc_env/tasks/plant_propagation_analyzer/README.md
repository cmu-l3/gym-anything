# Plant Propagation Analyzer Task

**Difficulty**: 🟡 Medium  
**Skills**: Date calculations, conditional counting, percentage analysis, conditional formatting  
**Duration**: 180 seconds  
**Steps**: ~25

## Objective

Analyze a propagation log to calculate success rates by method and identify optimal propagation techniques. This task tests date arithmetic, conditional counting (COUNTIF/COUNTIFS), percentage calculations, and conditional formatting to transform raw tracking data into actionable insights.

## Task Description

The agent must:
1. Open a spreadsheet with plant cutting propagation data
2. Calculate days elapsed since each cutting was taken (using TODAY() function)
3. Create a summary analysis table showing success rates by propagation method
4. Use COUNTIF/COUNTIFS to count attempts and successes
5. Calculate success rate percentages
6. Apply conditional formatting to highlight successful vs. failed cuttings

## Starting Data Structure

| Date Taken | Plant Species  | Propagation Method | Status  | Days Since Cutting |
|------------|----------------|-------------------|---------|-------------------|
| 2024-09-15 | Pothos         | Water             | Rooted  | (to calculate)    |
| 2024-10-01 | Monstera       | Soil              | Failed  | (to calculate)    |
| 2024-10-05 | Snake Plant    | Perlite           | Rooted  | (to calculate)    |
| ... (12 total data rows) ...                                                |

## Expected Analysis Table

To be created by agent around row 18:

| Propagation Method | Total Attempts | Successful | Success Rate |
|-------------------|----------------|------------|--------------|
| Water             | (COUNTIF)      | (COUNTIFS) | (formula %)  |
| Soil              | (COUNTIF)      | (COUNTIFS) | (formula %)  |
| Perlite           | (COUNTIF)      | (COUNTIFS) | (formula %)  |

## Success Criteria

1. ✅ **Days Calculated**: Days Since Cutting column contains TODAY()-based formulas for all data rows
2. ✅ **Summary Table Present**: Analysis table exists with Method, Total, Successful, Success Rate columns
3. ✅ **Counting Formulas Correct**: COUNTIF/COUNTIFS formulas accurately count by method and status
4. ✅ **Success Rates Accurate**: Calculated percentages match expected values (tolerance ±2%)
5. ✅ **Conditional Formatting Applied**: Status column has color rules for Rooted (green) and Failed (red)
6. ✅ **Percentage Formatting**: Success rate cells display as percentages
7. ✅ **Formula Coverage Complete**: All required cells contain formulas (not hardcoded values)

**Pass Threshold**: 70% (requires at least 5 out of 7 criteria)

## Skills Tested

- Date arithmetic with TODAY() function
- COUNTIF and COUNTIFS for conditional counting
- Percentage calculations and formatting
- Conditional formatting rules
- Absolute vs. relative cell references
- Summary table creation
- Formula copying and propagation

## Real-world Context

Amateur gardeners track propagation attempts to:
- Identify which methods work best for different plant species
- Reduce waste by avoiding ineffective techniques
- Improve success rates before attempting rare/expensive plants
- Make data-driven decisions about propagation timing and methods

## Tips

- Use `=TODAY()-A2` to calculate days since cutting date in column A
- Copy formula down using Ctrl+D or dragging fill handle
- Use absolute references `$A$2:$A$13` in COUNTIF formulas
- COUNTIFS syntax: `=COUNTIFS(range1, criteria1, range2, criteria2)`
- Format as percentage: Format → Cells → Percentage
- Conditional formatting: Format → Conditional Formatting → Condition
- Create separate rules for "Rooted" and "Failed" statuses