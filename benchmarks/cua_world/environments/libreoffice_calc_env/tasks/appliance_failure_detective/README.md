# Intermittent Appliance Failure Pattern Analyzer Task

**Task ID**: `appliance_failure_detective@1`  
**Difficulty**: 🟡 Medium  
**Estimated Steps**: 20-30  
**Timeout**: 180 seconds (3 minutes)

## Objective

Transform messy, chronologically-logged appliance failure data into a structured analysis that identifies failure patterns. This task tests data cleaning, conditional counting formulas, statistical analysis, and pattern recognition skills in a real-world scenario.

## Scenario

You've been documenting every dishwasher run for several months after noticing intermittent drainage failures. The warranty expires soon, and you need to prove to the manufacturer that there's a real pattern. Your log has inconsistent date formats (you used different devices to record), but the data is all there.

## Starting State

- LibreOffice Calc opens with a spreadsheet containing ~45 dishwasher run logs
- Columns: Date, Cycle Type, Load Size, Water Temp, Drainage Success, Notes
- Date formats are inconsistent (MM/DD/YYYY, M/D/YY, some text dates)
- Data spans several months with mixture of successful and failed runs

## Sample Data Structure

| Date | Cycle Type | Load Size | Water Temp | Drainage Success | Notes |
|------|------------|-----------|------------|------------------|-------|
| 3/15/2024 | Normal | Medium | Warm | Yes | Clean drain |
| 03/16/24 | Heavy | Full | Hot | No | Water remained |
| 3-17-2024 | Quick | Light | Cold | Yes | |
| March 18 2024 | Normal | Medium | Warm | Yes | |
| ... | ... | ... | ... | ... | ... |

## Required Actions

1. **Standardize Dates**: Create a cleaned date column with consistent format
2. **Sort Chronologically**: Sort all data by date (earliest to latest)
3. **Create Analysis Section**: Set up a separate area for failure rate calculations
4. **Calculate Failure Rates by Cycle Type**: Use COUNTIFS to compute failure % for Normal, Heavy, Quick
5. **Calculate Failure Rates by Load Size**: Compute failure % for Light, Medium, Full
6. **Calculate Failure Rates by Water Temp**: Compute failure % for Cold, Warm, Hot
7. **Identify Highest Risk**: Determine which condition has the highest failure rate
8. **Calculate Warranty Timeline**: Compute days since first failure
9. **Apply Formatting**: Format percentages and add conditional formatting for clarity

## Success Criteria

1. ✅ **Dates Standardized**: All dates in consistent format and chronologically sorted
2. ✅ **Analysis Structure Present**: Separate summary section with categorized failure rates
3. ✅ **Formulas Correct**: Failure rate calculations use proper COUNTIFS/COUNT logic
4. ✅ **Statistical Accuracy**: Calculated rates match actual data (±2% tolerance, spot-check 3+ categories)
5. ✅ **Highest Risk Identified**: Correctly identifies condition with maximum failure rate
6. ✅ **Warranty Timeline Calculated**: Days since first failure present and accurate (±2 days)
7. ✅ **Visual Clarity**: Percentage formatting and conditional highlighting applied

**Pass Threshold**: 70% (5 out of 7 criteria)

## Skills Tested

- Data cleaning and standardization
- Date handling and manipulation
- Conditional counting functions (COUNTIFS)
- Statistical calculation (failure rates)
- Formula creation with cell references
- Data sorting and organization
- Analytical reasoning and pattern identification
- Conditional formatting
- Percentage formatting

## Expected Analysis Structure
