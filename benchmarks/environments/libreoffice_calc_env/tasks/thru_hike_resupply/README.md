# Thru-Hike Resupply Calculator Task

**Difficulty**: 🟡 Medium  
**Skills**: Cumulative formulas, conditional logic, date arithmetic, data validation  
**Duration**: 180 seconds  
**Steps**: ~50

## Objective

Calculate resupply logistics for a 21-day Pacific Crest Trail section hike. Work with a partially-completed spreadsheet to calculate cumulative distances, determine food quantities needed, validate pace against terrain difficulty, and calculate arrival dates at resupply towns.

## Task Description

You are planning a 3-week section hike and need to finalize your resupply logistics. The spreadsheet contains:
- Daily mileage goals (some pre-filled)
- Terrain difficulty ratings
- Resupply town locations at specific points
- Empty columns for calculations

The agent must:
1. Calculate cumulative distance (running total)
2. Determine days of food needed between resupply points
3. Calculate food weight to carry (2 lbs per day)
4. Validate daily mileage is realistic for terrain difficulty
5. Calculate arrival dates at resupply towns (starting June 15, 2024)

## Expected Results

### Column Calculations:
- **Column D (Cumulative Distance)**: Running total of daily miles
- **Column F (Days to Next Resupply)**: Count of days until next town
- **Column G (Food Weight lbs)**: Days × 2.0 lbs per day
- **Column H (Pace Realistic?)**: "OK" or "UNREALISTIC" based on terrain
- **Column I (Date)**: Sequential dates starting June 15, 2024

### Terrain Pace Limits:
- Easy: ≤ 20 miles/day
- Moderate: ≤ 15 miles/day
- Hard: ≤ 12 miles/day
- Very Hard: ≤ 8 miles/day

## Verification Criteria

1. ✅ **Cumulative Distance Correct**: Column D shows accurate progressive totals
2. ✅ **Food Calculations Accurate**: Column G = Column F × 2.0
3. ✅ **Pace Validation Working**: Column H correctly flags unrealistic daily mileage
4. ✅ **Date Progression Correct**: Column I shows sequential dates from June 15
5. ✅ **Formulas Used**: Calculations use formulas, not hardcoded values
6. ✅ **Data Integrity**: Original data preserved, reasonable final totals

**Pass Threshold**: 70% (4/6 criteria must pass)

## Skills Tested

- Cumulative SUM formulas with cell references
- Conditional logic (IF statements)
- Date arithmetic
- Multi-step calculation chains
- Data validation and error detection
- Complex formula construction

## Data Structure

| Day | Daily Miles | Terrain    | Cumulative | Resupply Town | Days Food | Food Lbs | Realistic? | Date |
|-----|-------------|------------|------------|---------------|-----------|----------|------------|------|
| 1   | 14.5        | Moderate   | [FORMULA]  |               | [CALC]    | [CALC]   | [IF]       | [CALC] |
| ... | ...         | ...        | ...        | ...           | ...       | ...      | ...        | ...  |
| 5   | 11.8        | Moderate   | [FORMULA]  | Kennedy Mdw   | [CALC]    | [CALC]   | [IF]       | [CALC] |

## Tips

- Use cumulative formula pattern: `=D2+B3` (not SUM of entire range)
- For days to resupply, count rows until next non-empty cell in column E
- Food weight formula: `=F*2.0`
- IF statement for pace check: `=IF(B2>15,"UNREALISTIC","OK")` (adjust threshold per terrain)
- Date formula: Use starting date + day offset
- Total distance should be 180-280 miles for realistic 21-day section