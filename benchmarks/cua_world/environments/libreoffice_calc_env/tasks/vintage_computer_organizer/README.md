# Vintage Computer Collection Organizer Task

**Difficulty**: 🟡 Medium  
**Skills**: CSV import, complex formulas, conditional formatting, sorting, handling incomplete data  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Manage a vintage computer collection by importing existing data, adding new acquisitions with incomplete information, creating a multi-factor restoration priority scoring formula, applying conditional formatting to visualize priorities, and sorting the collection to identify which systems to restore first.

## Task Description

You are a vintage computer collector who just acquired several systems from an estate sale. You need to organize your expanding collection and decide which computers to restore first based on rarity, condition, and parts availability.

The agent must:
1. Open the existing collection CSV file (`vintage_computers.csv`)
2. Add 3-5 new computer entries from the estate sale (some with incomplete data like "Unknown" condition or missing Year)
3. Create a Priority_Score formula that weighs multiple factors:
   - **Rarity** (1-10 scale): weighted x2
   - **Condition Points**: Excellent=5, Good=3, Fair=2, Poor=1, Unknown=0
   - **Parts_Availability Points**: Easy=3, Moderate=2, Hard=1, Impossible=0
   - **Age Penalty**: (2024 - Year) / 10, rounded (older systems get slight penalty; use 1985 for missing years)
4. Apply conditional formatting to Priority_Score column:
   - **High Priority** (score ≥ 15): Green background
   - **Medium Priority** (score 10-14): Yellow background
   - **Low Priority** (score < 10): Red background
5. Sort the entire dataset by Priority_Score in descending order (highest priority first)
6. Save the file as ODS format

## Expected Results

- **All original data** from CSV preserved
- **3-5 new rows** added with realistic vintage computer data
- **Priority_Score column** (column H or similar) contains formulas calculating: `(Rarity * 2) + Condition_Points + Parts_Points - Age_Penalty`
- **Conditional formatting** applied showing green/yellow/red colors based on score thresholds
- **Data sorted** by Priority_Score descending (highest scores at top)
- **Row integrity** maintained (each computer's data stays together during sort)

## Verification Criteria

1. ✅ **Formula Present**: Priority_Score column contains formulas (not hardcoded values)
2. ✅ **Calculations Correct**: Spot-check of 2-3 rows shows accurate priority calculations
3. ✅ **Conditional Formatting**: Visual color coding applied to Priority_Score column
4. ✅ **Sorted Descending**: Priority scores decrease from top to bottom
5. ✅ **Data Integrity**: Row data remains coherent (Model matches its Priority_Score)
6. ✅ **Dataset Complete**: Original 10 entries + 3-5 new entries present

**Pass Threshold**: 80% (5/6 criteria must pass)

## Skills Tested

- CSV file import
- Cell navigation and data entry
- Complex multi-factor formulas with nested IF statements
- Handling missing/incomplete data in formulas
- Conditional formatting with multiple rules
- Data sorting with header row preservation
- File format conversion (CSV to ODS)

## Sample Priority Score Calculation

For **Apple II Plus** (Rarity=8, Condition=Good, Parts=Moderate, Year=1979):
- Base: Rarity × 2 = 8 × 2 = 16
- Condition: Good = 3
- Parts: Moderate = 2
- Age Penalty: (2024 - 1979) / 10 = 4.5 → 4 (rounded down)
- **Priority Score**: 16 + 3 + 2 - 4 = **17** (High Priority, Green)

For **Sinclair ZX Spectrum** (Rarity=9, Condition=Unknown, Parts=Hard, Year=missing):
- Base: Rarity × 2 = 9 × 2 = 18
- Condition: Unknown = 0
- Parts: Hard = 1
- Age Penalty: (2024 - 1985) / 10 = 3.9 → 3 (using default year)
- **Priority Score**: 18 + 0 + 1 - 3 = **16** (High Priority, Green)

## Tips

- Use `=IF()` or `=CHOOSE()` for mapping text conditions to numbers
- For missing Year values, use `=IF(ISBLANK(C2), 1985, C2)` pattern
- Use `=INT()` or `=ROUNDDOWN()` for age penalty calculation
- Apply conditional formatting: Format → Conditional Formatting → Condition
- When sorting: select entire data range including headers, Data → Sort, ensure "Range contains column labels" is checked