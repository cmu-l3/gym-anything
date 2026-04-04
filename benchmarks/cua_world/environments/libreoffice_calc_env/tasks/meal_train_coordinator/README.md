# Meal Train Coordinator Task

**Difficulty**: 🟡 Medium  
**Skills**: Conditional formulas, date arithmetic, data validation, summary statistics  
**Duration**: 300 seconds  
**Steps**: ~50

## Objective

Organize and validate a meal train schedule for a family with a new baby. The agent must identify scheduling conflicts (gaps, overlaps, dietary restriction mismatches) using formulas, and calculate summary statistics to ensure adequate coverage.

## Task Description

A community meal train spreadsheet has been partially filled by volunteers, but it contains errors:
- **Date gaps** where the family has no meal for >2 days
- **Duplicate dates** where multiple volunteers claimed the same day
- **Dietary issues** where meals don't accommodate restrictions (vegetarian, nut-free)
- **Delivery time conflicts** outside preferred windows

The agent must:
1. Add a formula to detect date gaps (>2 days between meals)
2. Add a formula to flag duplicate delivery dates
3. Add a formula to validate dietary compliance
4. Calculate summary statistics (total meals, coverage days, problem count)
5. Preserve original volunteer data

## Starting State

- LibreOffice Calc opens with `meal_train.csv`
- Columns: Date | Volunteer Name | Meal Type | Dietary Notes | Delivery Time | Contact
- 18 volunteer signups with planted issues

## Planted Issues (for testing)

1. **Gap**: April 5 → April 9 (4 days, no coverage)
2. **Duplicate**: Two volunteers on April 12
3. **Dietary**: "Chicken noodle soup" entry (family is vegetarian)
4. **Time**: Some deliveries outside 5:00-7:00 PM preference

## Expected Results

- **Helper columns** added for validation:
  - Days since last meal (to identify gaps)
  - Duplicate date flag
  - Dietary compliance check
  - Delivery time validation
- **Summary section** with:
  - Total meals count (~18)
  - Date range coverage (~21-28 days)
  - Problem count (3-5 issues)

## Verification Criteria

1. ✅ **Gap Detection Works**: Formula identifies meals >2 days apart
2. ✅ **Duplicate Detection Works**: Formula flags duplicate April 12 entries
3. ✅ **Dietary Validation Works**: Formula identifies chicken soup issue
4. ✅ **Summary Statistics Present**: At least 2 key metrics calculated
5. ✅ **Formula Accuracy**: Summary values within tolerance
6. ✅ **Data Integrity**: Original volunteer information preserved

**Pass Threshold**: 70% (4/6 criteria must pass)

## Skills Tested

- Date arithmetic (calculating gaps between dates)
- Conditional logic (IF, AND, OR, COUNTIF)
- Text search (SEARCH, FIND for dietary keywords)
- Summary aggregation (COUNT, SUM, MAX, MIN)
- Data validation and quality checking
- Real-world problem-solving

## Tips

- Sort data by date first to make gap detection easier
- Use COUNTIF to find duplicate dates
- Use SEARCH or FIND to check for restricted ingredients
- Create helper columns for each validation check
- Add summary section at bottom or side of data
- Test formulas against known issues (April 5-9 gap, April 12 duplicate)

## Formula Examples

**Gap Detection:**