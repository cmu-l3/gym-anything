# Manuscript Submission Tracker Task

**Difficulty**: 🟡 Medium  
**Skills**: Data cleaning, date calculations, conditional formulas, aggregation  
**Duration**: 300 seconds (5 minutes)  
**Steps**: ~20

## Objective

Clean up and analyze a messy manuscript submission tracking spreadsheet for a freelance writer. Transform disorganized records with inconsistent formatting into actionable insights by standardizing status values, calculating response times, and generating publication statistics.

## Task Description

**Scenario**: You're a freelance writer who has been tracking story submissions to literary magazines in a spreadsheet. Over months of usage, your data entry has become inconsistent—some statuses are abbreviated ("R" for rejected), dates are in different formats, and you need to calculate which publications are worth targeting based on acceptance rates and response times.

The agent must:
1. **Standardize Status Values**: Convert variants like "reject", "R", "No thanks" → "Rejected"
2. **Fix Date Formatting**: Make all dates consistent and parseable
3. **Calculate Response Times**: Add formula column for days between submission and response
4. **Generate Publication Statistics**: Create summary table with acceptance rates and average response times
5. **Calculate Overall Metrics**: Total submissions, overall acceptance rate, pending count
6. **Ensure Data Quality**: No formula errors, logical consistency checks

## Starting Data Issues

The provided spreadsheet contains realistic messiness:
- **Inconsistent Statuses**: "Rejected", "reject", "R", "No thanks", "Accepted", "acc", "Pending", blank
- **Mixed Date Formats**: Some MM/DD/YYYY, some DD-Mon-YYYY, some text like "March 15, 2024"
- **Missing Response Dates**: Pending submissions have blank Response Date cells
- **Incomplete Status**: Some entries missing status entirely

## Expected Results

### Cleaned Data
- **Status Column**: Only "Accepted", "Rejected", "Pending", "Withdrawn"
- **Date Columns**: Consistent format across all entries
- **Days to Response**: New column with formula: blank/pending for ongoing, calculated days for completed

### Publication Summary Table
For each publication:
- Total Submissions
- Accepted Count
- Rejected Count  
- Pending Count
- Acceptance Rate (%)
- Average Response Time (days)

### Overall Statistics
- Total submissions across all publications
- Overall acceptance rate
- Count of pending submissions
- Number pending > 90 days

## Verification Criteria

1. ✅ **Status Standardized**: Only canonical status values present
2. ✅ **Dates Formatted**: All dates in consistent format and valid
3. ✅ **Response Time Calculated**: New column with correct conditional formulas
4. ✅ **Publication Summary**: Summary table with required metrics per publication
5. ✅ **Overall Statistics**: Global metrics calculated correctly
6. ✅ **Formula Accuracy**: Statistics within tolerance (±0.5% for rates, ±1 day for averages)
7. ✅ **No Formula Errors**: No #VALUE!, #DIV/0!, #REF! errors
8. ✅ **Logical Consistency**: No invalid date relationships

**Pass Threshold**: 75% (6/8 criteria must pass)

## Skills Tested

- **Data Quality Assessment**: Identify systematic issues vs one-off errors
- **Find & Replace**: Standardize text values efficiently
- **Date Functions**: DATEDIF, TODAY, ISBLANK for date arithmetic
- **Conditional Logic**: IF statements with nested conditions
- **Aggregation Functions**: COUNTIF, SUMIF, AVERAGEIF for statistics
- **Formula Construction**: Complex formulas with cell references
- **Data Analysis**: Transform raw data into decision support insights

## Tips

- Use Edit → Find & Replace to standardize status values efficiently
- The DATEDIF function calculates days between dates: `=DATEDIF(start, end, "D")`
- Use ISBLANK to check if Response Date is empty: `=IF(ISBLANK(D2),"Pending", ...)`
- COUNTIF counts cells matching criteria: `=COUNTIF(range, criteria)`
- AVERAGEIF calculates average excluding certain values
- Remember to use $ for absolute references in formulas that will be copied
- Sort by acceptance rate to identify best-performing publications