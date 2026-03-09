# Gym Class Sign-up Penalty Calculator Task

**Difficulty**: 🟡 Medium  
**Skills**: Conditional logic, date/time calculations, data cleaning, multi-sheet formulas, fairness analysis  
**Duration**: 300 seconds (5 minutes)  
**Steps**: ~25

## Objective

Manage a community gym's group fitness class reservation system by analyzing attendance data, calculating penalty points for chronic no-shows, identifying members requiring warnings or booking restrictions, and auditing the fairness of the penalty system. This task simulates real-world resource allocation problems where limited class spots are wasted by no-shows.

## Real-World Context

A small community gym with 300 members offers popular group fitness classes (spin, yoga, HIIT). Each class has 15-20 spots. Members can book up to 3 classes per week but must cancel at least 2 hours before class start or face penalties. The gym manager needs help calculating strikes, issuing warnings, and ensuring the penalty system is fair across all member demographics.

## Task Description

The agent must:
1. Open a provided ODS file with three sheets: **Bookings**, **Members**, **Rules**
2. Clean data (remove duplicate bookings, standardize member names)
3. Calculate hours between cancellation and class time
4. Determine which no-shows earn "strikes" (late cancels or no-shows)
5. Calculate rolling 30-day strike counts per member
6. Assign penalty status: GOOD_STANDING, WARNING (2 strikes), or RESTRICTED (3+ strikes)
7. Apply conditional formatting (green/yellow/red backgrounds)
8. Perform fairness audit (check if penalties disproportionately affect any demographic group)
9. Generate summary reports

## Data Structure

### Bookings Sheet
- Columns: member_id, class_date, class_time, booking_timestamp, cancellation_timestamp, attended, excuse_code
- 200 booking records over 90 days
- Includes data quality issues: duplicates, missing timestamps, inconsistent formatting

### Members Sheet
- Columns: member_id, name, age_group, membership_type, join_date
- 50 member profiles
- Demographic information for fairness analysis

### Rules Sheet
- Penalty parameters:
  - grace_period_hours = 2 (must cancel 2+ hours before class)
  - strikes_for_warning = 2
  - strikes_for_restriction = 3
  - rolling_window_days = 30

## Expected Results

### New Columns/Calculations Required

1. **hours_before_class** (Bookings sheet)
   - Formula: Calculate hours between cancellation_timestamp and class_date+class_time
   - Handle cases where cancellation_timestamp is empty (set to 0)

2. **strike_earned** (Bookings sheet)
   - 0 if attended = TRUE
   - 0 if hours_before_class >= grace_period_hours (timely cancel)
   - 0 if excuse_code is not empty (excused absence)
   - 1 otherwise (late cancel or no-show)

3. **Member_Penalties** (new sheet)
   - member_id, name, rolling_strike_count, penalty_status, most_recent_no_show
   - rolling_strike_count: Count strikes in last 30 days using COUNTIFS
   - penalty_status: "GOOD_STANDING", "WARNING", or "RESTRICTED"
   - Conditional formatting: Red (RESTRICTED), Yellow (WARNING), Green (GOOD_STANDING)

4. **Fairness_Summary** (new sheet)
   - demographic_group, avg_strikes, pct_of_overall_avg, fairness_flag
   - Calculate average strikes by age_group and membership_type
   - Flag if any group's average is >1.5x overall average

## Verification Criteria

1. ✅ **Hours Calculation**: hours_before_class correctly computed (±0.5 hour tolerance)
2. ✅ **Strike Logic**: strike_earned applies rules correctly (grace period, excuse codes)
3. ✅ **Rolling Count Accurate**: rolling_strike_count uses 30-day window correctly
4. ✅ **Penalty Status Correct**: Members categorized correctly (RESTRICTED = 3+ strikes, WARNING = 2)
5. ✅ **Fairness Audit**: No demographic group flagged for bias (avg >1.5x overall)
6. ✅ **Data Cleaned**: Duplicates removed, names standardized
7. ✅ **Conditional Formatting**: Color coding applied to penalty_status
8. ✅ **Summary Sheets**: Member_Penalties and Fairness_Summary exist with correct data

**Pass Threshold**: 85% (7/8 criteria must pass)

## Skills Tested

- Multi-sheet workbook navigation
- Date/time arithmetic (HOUR, DATE functions)
- Conditional aggregation (COUNTIFS, SUMIFS, AVERAGEIFS)
- Nested IF statements with AND/OR logic
- Data cleaning (deduplication, text standardization)
- Lookup functions (VLOOKUP, INDEX-MATCH)
- Conditional formatting application
- Statistical analysis (averages, standard deviation)
- Named range usage
- Cross-sheet formulas

## Tips

- Use COUNTIFS with date criteria to count strikes in rolling 30-day window
- Calculate hours using: `=(cancellation_timestamp - (class_date + class_time)) * 24`
- Use IF(ISBLANK(...)) to handle missing cancellation timestamps
- Apply PROPER() and TRIM() functions to standardize names
- Use conditional formatting rules: Format → Conditional → Condition
- Reference Rules sheet parameters using absolute references (e.g., Rules.$B$2)
- Sort by rolling_strike_count descending to see worst offenders first