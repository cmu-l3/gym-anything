# Meal Train Conflict Resolver Task

**Difficulty**: 🟡 Medium  
**Skills**: Conditional logic, data validation, conflict resolution, date handling  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Organize and resolve conflicts in a community meal train spreadsheet. A neighbor (Sarah) recovering from surgery needs 14 consecutive days of vegetarian dinners (March 1-14, 2025). Community members signed up via a shared spreadsheet, but predictable problems emerged: duplicate date assignments, uncovered dates, non-vegetarian meals selected, and poor dish variety. The agent must identify conflicts, flag dietary violations, fill gaps, and ensure complete coverage with appropriate meals.

## Task Description

The agent must:
1. Review the meal train signup spreadsheet with existing conflicts
2. Identify dates where multiple volunteers signed up (duplicates)
3. Identify dates within the 14-day period with no coverage (gaps)
4. Flag meals containing meat (dietary violations for vegetarian family)
5. Add analysis columns to track conflicts and dietary compliance
6. Resolve conflicts by reassigning volunteers or flagging issues
7. Ensure complete 14-day coverage with all-vegetarian meals
8. Create summary statistics showing coverage status

## Starting Data Issues

The spreadsheet contains intentional problems:
- **Duplicate dates**: March 3 and March 11 each have 2 signups
- **Coverage gaps**: March 7 and March 10 have no signups
- **Dietary violations**: March 5 (Meatloaf) and March 9 (BBQ Chicken) contain meat
- **Total**: 17 signups for 14 dates with 2 gaps and 2 violations

## Expected Results

After resolution:
- **Complete coverage**: All 14 dates (March 1-14) have exactly one meal
- **Dietary compliance**: All meals are vegetarian (Contains_Meat = "No")
- **Conflict analysis**: Added columns flagging duplicates and violations
- **Gap resolution**: Previously uncovered dates now have assignments
- **Summary statistics**: Counts of total dates, conflicts, gaps, violations

## Verification Criteria

1. ✅ **Complete Coverage**: All 14 required dates have exactly one meal assignment
2. ✅ **Dietary Compliance**: Zero meat-containing meals (100% vegetarian)
3. ✅ **No Date Conflicts**: Each date appears exactly once (no duplicates)
4. ✅ **Conflict Identified**: Evidence of conflict analysis (flag columns or notes)
5. ✅ **Gap Resolution**: Original missing dates now have assignments
6. ✅ **Summary Present**: Coverage statistics calculated

**Pass Threshold**: 70% (requires at least 4 out of 6 criteria)

## Skills Tested

- Conditional formula creation (IF statements)
- Duplicate detection (COUNTIF)
- Gap identification (date range verification)
- Categorical data validation
- Data cleaning and organization
- Multi-constraint problem solving

## Tips

- Use COUNTIF to detect duplicate dates: `=COUNTIF($A$2:$A$50, A2)`
- Add a "Conflict_Flag" column to mark issues
- Create a reference list of all 14 required dates
- Use IF formulas to check dietary compliance: `=IF(D2="Yes", "⚠️ NOT VEGETARIAN", "✓ OK")`
- For duplicates, keep one volunteer and move the other to a gap date
- Add summary formulas at the top to count conflicts and coverage