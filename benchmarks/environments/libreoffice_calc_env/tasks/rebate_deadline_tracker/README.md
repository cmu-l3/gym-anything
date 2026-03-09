# Rebate Deadline Tracker Task

**Difficulty**: 🟡 Medium  
**Skills**: Date functions, data cleaning, conditional formatting, sorting, financial formulas  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Clean, standardize, and augment a partially-complete consumer rebate tracking spreadsheet with time-sensitive deadline calculations. The agent must handle inconsistent date formats, calculate days remaining, identify at-risk rebates, standardize status fields, and apply conditional formatting.

## Task Description

A consumer has been tracking mail-in rebates but the spreadsheet is messy with inconsistent formats and incomplete calculations. The agent must:

1. **Clean Date Formats** - Standardize mixed date formats in Purchase Date column
2. **Calculate Missing Deadlines** - Use formula: Purchase Date + Validity Period
3. **Calculate Days Remaining** - Use TODAY() function to determine urgency
4. **Standardize Status Field** - Convert varied entries to consistent values
5. **Add Priority Classification** - Create urgency categories (URGENT, Soon, OK, etc.)
6. **Apply Conditional Formatting** - Color-code priorities for visual impact
7. **Calculate Financial Totals** - Use SUMIF to track pending and at-risk amounts
8. **Sort by Urgency** - Prioritize urgent, high-value rebates

## Starting Data Structure

| Product | Purchase Date | Rebate Amount | Validity Period | Deadline | Days Remaining | Status | Notes |
|---------|--------------|---------------|----------------|----------|----------------|--------|-------|
| (10 rows with intentional messiness) |

**Intentional Issues:**
- Mixed date formats (MM/DD/YYYY, DD-MM-YYYY)
- Inconsistent status ("Submitted", "sent", "pending", "MAILED")
- Currency with/without $ symbols
- Empty deadline and days remaining cells
- Trailing spaces in text fields

## Expected Results

**Cleaned Data:**
- All dates in consistent format
- All deadlines calculated
- Days remaining calculated using TODAY()
- Status standardized to: "Submitted", "Pending", "Expired"
- Priority column with values: URGENT, Soon, OK, Complete, MISSED, EXPIRED
- Conditional formatting applied (Red=URGENT, Yellow=Soon, Green=OK)
- Financial totals at bottom
- Data sorted by priority and amount

## Verification Criteria

1. ✅ **Dates Standardized** (100% of purchase dates are valid date values)
2. ✅ **Deadlines Complete** (All deadline cells populated with valid dates)
3. ✅ **Days Remaining Accurate** (Calculated values match date arithmetic ±1 day)
4. ✅ **Status Standardized** (Only 3 distinct status values)
5. ✅ **Priority Correctly Classified** (≥80% match expected logic)
6. ✅ **Financial Totals Accurate** (SUMIF formulas correct ±$1)
7. ✅ **Conditional Formatting Applied** (Formatting rules exist)
8. ✅ **Data Sorted** (URGENT items in top 50% of rows)

**Pass Threshold**: 70% (6 out of 8 criteria)

## Skills Tested

- Date function mastery (TODAY, DATEVALUE, date arithmetic)
- Data cleaning and standardization
- Nested IF logic for classification
- Conditional formatting rules
- SUMIF for category totals
- Multi-level sorting
- Cell reference management

## Real-World Context

Mail-in rebates are notoriously tedious with strict deadlines. Missing a deadline means losing real money. This task simulates the frustration of managing rebate paperwork where data is entered piecemeal over weeks as receipts are found.

## Tips

- Use Find & Replace for status standardization
- DATEVALUE() converts text dates to proper dates
- TODAY() function updates automatically
- Nested IF: `=IF(condition1, value1, IF(condition2, value2, ...))`
- SUMIF syntax: `=SUMIF(range, criteria, sum_range)`
- Conditional formatting: Format → Conditional → Color Scale/Condition