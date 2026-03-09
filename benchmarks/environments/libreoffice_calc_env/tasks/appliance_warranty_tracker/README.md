# Appliance Warranty Tracker Task

**Difficulty**: 🟡 Medium  
**Skills**: Date functions, conditional logic, conditional formatting  
**Duration**: 180 seconds  
**Steps**: ~50

## Objective

Create a practical warranty tracking system for household appliances by calculating expiration dates, determining time remaining, applying status logic, and using conditional formatting for visual alerts. This task addresses the real-world problem of lost receipts and forgotten warranty deadlines.

## Task Description

The agent must:
1. Open a CSV file containing appliance purchase records (5 appliances)
2. Create "Warranty Expiration Date" column using date addition formulas
3. Create "Days Remaining" column using TODAY() function
4. Create "Status" column with nested IF logic (Expired/Expiring Soon/Active)
5. Apply conditional formatting to the Status column with color coding
6. Save the file as ODS format

## Starting Data

CSV contains 5 appliances with:
- Appliance Name
- Purchase Date
- Warranty Months (12, 24, 36, or 120 months)
- Receipt Location (Filing Cabinet, Digital, Lost)
- Manual Location (various household locations)

## Expected Results

**New Columns to Create:**

- **Column F (Warranty Expiration Date)**: 
  - Formula: `=EDATE(B2,C2)` or `=DATE(YEAR(B2),MONTH(B2)+C2,DAY(B2))`
  - Adds warranty months to purchase date

- **Column G (Days Remaining)**:
  - Formula: `=F2-TODAY()`
  - Calculates days until warranty expires

- **Column H (Status)**:
  - Formula: `=IF(G2<0,"Expired",IF(G2<90,"Expiring Soon","Active"))`
  - Categorizes warranty status based on days remaining

**Conditional Formatting:**
- Status column should have color coding:
  - "Expired" → Red background or text
  - "Expiring Soon" → Yellow/Orange background
  - "Active" → Green background or normal appearance

## Verification Criteria

1. ✅ **Expiration Date Formula**: Uses EDATE or DATE with month addition, results accurate (±3 days)
2. ✅ **Days Remaining Formula**: Properly subtracts TODAY() from expiration date (±1 day)
3. ✅ **Status Logic**: Nested IF correctly categorizes based on days remaining
4. ✅ **All Rows Calculated**: Formulas applied to all 5 appliance entries
5. ✅ **Conditional Formatting Applied**: Status column has visual formatting rules
6. ✅ **Appropriate Color Scheme**: Uses warning colors appropriately

**Pass Threshold**: 70% (requires at least 4 out of 6 criteria)

## Skills Tested

- Date arithmetic and EDATE function
- TODAY() function usage
- Nested IF statements
- Conditional formatting application
- Cell reference management
- Practical data organization

## Tips

- EDATE(date, months) is the easiest way to add months to a date
- Alternative: DATE(YEAR(B2), MONTH(B2)+C2, DAY(B2))
- TODAY() returns the current date (updates automatically)
- Nested IF syntax: IF(condition1, value1, IF(condition2, value2, value3))
- Conditional formatting: Format → Conditional Formatting → Condition
- Apply formatting rules based on cell text content