# Houseplant Watering Schedule Task

**Difficulty**: 🟡 Medium  
**Skills**: Date formulas, conditional logic, conditional formatting, sorting  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Create a dynamic watering schedule for a houseplant collection with varying watering needs. This task tests date arithmetic, conditional formulas, visual formatting, and data organization skills used in real-world personal task management.

## Task Description

You are a plant enthusiast with a growing collection. After forgetting to water your fiddle leaf fig and watching it drop leaves, you need a systematic schedule that automatically tells you which plants need attention each day.

The agent must:
1. Work with provided CSV data containing: Plant Name, Location, Last Watered Date, Frequency (days)
2. Add "Next Watering Due" column with date formula (Last Watered + Frequency)
3. Add "Days Until Watering" column with formula (Next Due - TODAY())
4. Add "Priority" column with conditional logic:
   - "OVERDUE" if days until < 0
   - "TODAY" if days until = 0
   - "SOON" if days until ≤ 2
   - "OK" if days until > 2
5. Apply conditional formatting with color coding (red=OVERDUE, yellow/orange=TODAY/SOON, green=OK)
6. Sort data by Next Watering Due (earliest first)
7. Save as ODS file

## Expected Results

- **Column E (Next Watering Due)**: Formula `=C2+D2` calculating future dates
- **Column F (Days Until)**: Formula `=E2-TODAY()` showing days remaining
- **Column G (Priority)**: Nested IF formula categorizing urgency
- **Conditional Formatting**: Visual color coding applied to priority or data range
- **Sorted Data**: Rows ordered by Next Watering Due ascending

## Verification Criteria

1. ✅ **Formulas Correct**: Next Due, Days Until, and Priority formulas structurally correct (25 points)
2. ✅ **Calculations Accurate**: Spot-checked rows show correct date arithmetic (25 points)
3. ✅ **Conditional Formatting Applied**: Visual formatting detected (20 points)
4. ✅ **Data Sorted**: Rows ordered by Next Watering Due (20 points)
5. ✅ **No Formula Errors**: All cells contain values, not #VALUE! or #REF! (10 points)

**Pass Threshold**: 75% (requires correct formulas, accurate calculations, and formatting OR sorting)

## Skills Tested

- Date function usage (TODAY(), date arithmetic)
- Conditional logic (nested IF statements)
- Cell references (relative vs absolute)
- Conditional formatting application
- Data sorting operations
- Formula propagation across rows

## Real-World Context

This represents a genuine personal organization workflow. Plant owners with 10-20+ plants use spreadsheets like this to avoid forgetting watering schedules. The TODAY() function makes it dynamic—open the spreadsheet any day and immediately see which plants need attention.

## Tips

- Date arithmetic in Calc: adding numbers to dates adds days
- TODAY() function returns current date and updates automatically
- Nested IF syntax: `=IF(condition1, result1, IF(condition2, result2, default))`
- Conditional formatting: Format → Conditional → Condition
- Sort: Select data range → Data → Sort → choose column