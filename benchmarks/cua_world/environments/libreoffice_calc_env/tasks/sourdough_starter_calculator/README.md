# Sourdough Starter Activity Calculator Task

**Difficulty**: 🟡 Medium  
**Skills**: Formula creation, conditional logic, percentage calculations, data analysis  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Work with a sourdough starter feeding log to calculate key baking metrics through formulas. The agent must compute hydration percentages, total flour consumption, apply conditional logic for readiness flags, and handle real-world data. This represents practical home baking workflow management requiring formula expertise, conditional logic, and data analysis skills.

## Task Description

The agent must:
1. Open a CSV file containing sourdough starter feeding log data
2. Calculate **Total Weight After Feed** = starter_weight + flour_added + water_added
3. Calculate **Hydration Percentage** = (water_added / flour_added) * 100
4. Determine **Hours to Peak** based on room temperature (conditional formula)
5. Create **Ready to Bake?** flag using conditional logic (hours + weight criteria)
6. Calculate **Total Flour Used** across all feedings (SUM)
7. Calculate **Average Hydration %** across all feedings (AVERAGE)
8. Save the enhanced spreadsheet

## Starting Data Structure

The CSV contains feeding log entries with columns:
- Date (e.g., "2024-01-15")
- Time (e.g., "08:00")
- Starter_Weight_g (grams before feeding)
- Flour_Added_g (grams of flour added)
- Water_Added_g (grams of water added)
- Room_Temp_C (room temperature in Celsius)
- Hours_Since_Feed (time since last feeding)

## Required Calculations

### 1. Total Weight After Feed (Column H)
Formula: `=C2+D2+E2` (starter + flour + water)

### 2. Hydration Percentage (Column I)
Formula: `=(E2/D2)*100` (water/flour as percentage)
Handle divide-by-zero errors if needed

### 3. Hours to Peak (Column J) - Optional Enhancement
Simplified estimation based on temperature:
- If temp >= 24°C: ~5 hours
- If temp >= 20°C: ~7 hours
- If temp < 20°C: ~10 hours

Formula example: `=IF(F2>=24, 5, IF(F2>=20, 7, 10))`

### 4. Ready to Bake? (Column K)
Criteria: Hours since feed between 3-8 AND total weight >= 150g
Formula: `=IF(AND(G2>=3, G2<=8, H2>=150), "YES", "NO")`

### 5. Summary Calculations
- **Total Flour Used**: Place below data table, use `=SUM(D:D)` or range
- **Average Hydration**: Place below data table, use `=AVERAGE(I:I)` or range

## Expected Results

Sample row calculation:
- Starter: 50g, Flour: 50g, Water: 50g
- Total Weight = 150g
- Hydration = 100%
- If hours_since_feed = 5, ready = "YES"

## Verification Criteria

1. ✅ **Hydration Formula Present**: Column contains formula calculating (water/flour)*100
2. ✅ **Total Weight Formula Present**: Column contains formula summing components
3. ✅ **Readiness Logic Implemented**: IF/AND formula determines baking readiness
4. ✅ **Total Flour Calculated**: SUM formula aggregates flour additions
5. ✅ **Values Within Range**: Hydration 70-150%, readiness flags logically consistent
6. ✅ **Average Hydration Calculated**: AVERAGE function computes mean hydration

**Pass Threshold**: 75% (requires at least 5 out of 6 criteria)

## Skills Tested

- Formula creation with cell references
- Arithmetic operations in formulas
- Percentage calculations
- Conditional logic (IF, AND functions)
- Aggregate functions (SUM, AVERAGE)
- Error handling (IFERROR for division)
- Data analysis and interpretation
- Domain-specific problem solving

## Tips

- Add new columns to the right of existing data (columns H, I, J, K)
- Use column references (e.g., D2) rather than hardcoded values
- Copy formulas down to apply to all rows
- For summary cells, place them below the data table
- Test your formulas with the first data row before copying down
- Hydration percentage should typically be 80-120% for normal starters