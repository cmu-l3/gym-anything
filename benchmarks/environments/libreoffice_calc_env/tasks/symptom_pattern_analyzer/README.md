# Symptom Pattern Analyzer Task

**Difficulty**: 🟡 Medium  
**Skills**: Date functions, formula creation, data analysis, statistical functions  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Transform a messy symptom tracking log into an analytical spreadsheet with helper columns and summary statistics. This task simulates preparing scattered health notes for a medical consultation, requiring data cleaning, temporal analysis, and pattern detection.

## Task Description

The agent must:
1. Open a symptom log spreadsheet with inconsistent tracking data (28 days, 12-15 entries)
2. Add analytical helper columns:
   - **Day_of_Week**: Extract day name from date (e.g., "Monday", "Tuesday")
   - **Days_Since_Last**: Calculate days between consecutive episodes
   - **Is_Weekend**: Classify as weekend ("Yes") or weekday ("No")
3. Create summary statistics section with formulas:
   - **Total Episodes**: Count of logged entries
   - **Average Severity**: Mean severity rating
   - **Days Covered**: Date range span
   - **Average Days Between Episodes**: Mean interval
   - **Weekend Episode Count**: Episodes on Sat/Sun
   - **Weekday Episode Count**: Episodes on Mon-Fri
4. Use formulas (not hardcoded values) for all calculations
5. Preserve original data integrity

## Starting Data Structure

| Date | Time | Severity (1-10) | Symptoms_Text | Possible_Trigger |
|------|------|----------------|---------------|------------------|
| Various dates | Various times | 3-9 (some blank) | Description | Trigger notes |

**Data Characteristics:**
- Irregular logging intervals (1-5 days between entries)
- Some missing severity ratings
- Mix of date formats
- Weekend clustering intentionally present

## Expected Results

**New Columns:**
- **Column F (Day_of_Week)**: Day names using TEXT() or WEEKDAY() formulas
- **Column G (Days_Since_Last)**: Numeric intervals using date arithmetic
- **Column H (Is_Weekend)**: "Yes"/"No" using IF() + WEEKDAY() logic

**Summary Section:**
- All metrics calculated using formulas (COUNT, AVERAGE, MAX, MIN, COUNTIF)
- Accurate values matching independent calculation (within tolerance)

## Verification Criteria

1. ✅ **Day_of_Week Column**: Present with proper day name formulas
2. ✅ **Days_Since_Last Column**: Present with date arithmetic formulas
3. ✅ **Is_Weekend Column**: Present with weekday classification logic
4. ✅ **Summary Statistics Accurate**: All metrics correct (±0.5 tolerance)
5. ✅ **Formulas Used**: Summary cells contain formulas, not typed values
6. ✅ **Original Data Preserved**: Source columns unchanged

**Pass Threshold**: 70% (4/6 criteria must pass)

## Skills Tested

- Date/time function mastery (TEXT, WEEKDAY, date arithmetic)
- Formula construction with cell references
- Conditional logic (IF, AND, OR)
- Statistical functions (AVERAGE, COUNT, COUNTIF)
- Data quality assessment
- Missing data handling
- Temporal pattern analysis

## Tips

- Use `=TEXT(A2,"dddd")` or `=TEXT(A2,"ddd")` for day names
- Date arithmetic: `=A3-A2` calculates days between dates
- Weekend detection: `=IF(OR(WEEKDAY(A2)=1,WEEKDAY(A2)=7),"Yes","No")`
- Or: `=IF(OR(TEXT(A2,"dddd")="Saturday",TEXT(A2,"dddd")="Sunday"),"Yes","No")`
- AVERAGE function automatically excludes blank cells
- Use COUNTIF for conditional counting: `=COUNTIF(H:H,"Yes")`

## Context

This task simulates real-world health tracking where someone has been logging symptoms inconsistently for a month and needs to analyze patterns before a doctor appointment. The urgency and practical application make this a valuable life skill beyond spreadsheet proficiency.