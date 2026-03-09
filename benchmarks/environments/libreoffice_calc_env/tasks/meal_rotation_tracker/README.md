# Meal Rotation Tracker Task

**Difficulty**: 🟡 Medium  
**Skills**: Date formulas, COUNTIF, MAXIFS, conditional formatting, data analysis  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Analyze a family meal log to prevent repetitive meal planning by calculating "days since last eaten" for common meals, identifying frequency patterns, and applying visual indicators for meal rotation planning.

## Task Description

A family has been logging their dinners for the past 60 days but keeps accidentally repeating the same meals too frequently. The agent must:

1. Open the provided meal log spreadsheet (60 days of Date + Meal Name)
2. Create a summary analysis section listing 5-8 common meals
3. Add formulas to calculate "days since last eaten" for each meal using TODAY() and MAXIFS()
4. Add formulas to count how many times each meal appears using COUNTIF()
5. Apply conditional formatting to highlight meals that are:
   - **Green** (≥21 days): Overdue, good to make
   - **Red** (≤7 days): Recently eaten, should avoid
6. Save the enhanced spreadsheet

## Expected Results

### Summary Section Structure
- Column with meal names (e.g., "Spaghetti", "Tacos", "Pizza")
- Column with "Days Since Last Eaten" formulas: `=TODAY() - MAXIFS($A:$A, $B:$B, E3)`
- Column with "Times Eaten" formulas: `=COUNTIF($B:$B, E3)`
- Conditional formatting applied to "Days Since" column

### Example Layout

| Meal            | Days Since Last Eaten | Times Eaten (60 days) |
|-----------------|----------------------|-----------------------|
| Spaghetti       | 23 (green)          | 8                     |
| Tacos           | 4 (red)             | 6                     |
| Chicken Stir-fry| 15                  | 5                     |
| Pizza           | 28 (green)          | 7                     |

## Verification Criteria

1. ✅ **Formulas Present**: "Days Since" uses TODAY() and MAXIFS (or MAX+IF)
2. ✅ **Frequency Formulas**: COUNTIF formulas correctly count meal occurrences
3. ✅ **Calculations Valid**: All formulas produce numeric results (0-60 day range)
4. ✅ **Green Formatting**: Cells with ≥21 days have green background
5. ✅ **Red Formatting**: Cells with ≤7 days have red background
6. ✅ **Summary Structure**: Organized section with meal names and calculations
7. ✅ **No Errors**: No formula errors (#VALUE!, #REF!, etc.)

**Pass Threshold**: 70% (5/7 criteria must pass)

## Skills Tested

- Date arithmetic (TODAY(), date differences)
- Advanced lookup functions (MAXIFS with conditions)
- Counting functions (COUNTIF)
- Conditional formatting with value-based rules
- Absolute vs. relative cell references ($A$1 vs. A1)
- Data analysis and pattern recognition
- Spreadsheet organization and layout

## Starting Data

The meal log contains 60 rows:
- **Column A**: Date (going back 60 days)
- **Column B**: Meal Name (realistic dinner entries)

Common meals include: Spaghetti, Tacos, Chicken Stir-fry, Pizza, Grilled Salmon, Beef Chili, Roast Chicken, Burgers, Lasagna

## Tips

- Select a clear area (e.g., columns E-G) for your summary section
- Use absolute references ($A:$A, $B:$B) in formulas so they work when copied down
- MAXIFS syntax: `=MAXIFS(range_to_max, criteria_range, criterion)`
- Apply conditional formatting: Format → Conditional Formatting → Condition
- Test formulas on one meal first, then copy down to others
- TODAY() returns the current date, so "days since" = TODAY() - most_recent_date

## Real-World Context

This task represents a common household frustration: tracking meal variety without a systematic approach. The solution applies spreadsheet analysis to provide:
- **Visual cues** for which meals are overdue (green) or too recent (red)
- **Frequency data** to identify over-relied-upon meals
- **Objective metrics** to support more diverse meal planning

Similar approaches apply to:
- Exercise rotation tracking
- Plant watering schedules
- Cleaning task rotation
- Medication/supplement variety