# Professional Certification Renewal Manager Task

**Difficulty**: 🟡 Medium  
**Skills**: Date calculations, conditional logic, conditional formatting, sorting, financial formulas  
**Duration**: 180 seconds (3 minutes)  
**Steps**: ~12

## Objective

Transform a basic certification tracking spreadsheet into an actionable compliance dashboard by calculating expiration urgency, applying conditional formatting for visual alerts, aggregating renewal costs, and organizing certifications by priority. This task tests date manipulation, conditional logic, formatting, and data organization skills.

## Rationale

**Real-world professional stakes**: Healthcare workers, teachers, engineers, financial advisors, pilots, and many professionals must track certification renewals. Lapsed certifications can legally prevent professionals from working. This task simulates actual compliance tracking used in high-stakes professional environments.

## Starting State

- LibreOffice Calc opens with a certification tracking spreadsheet
- Data contains: Certification Name, Issuing Body, Expiration Date, Renewal Cost, CE Credits Required, CE Credits Completed
- 7 certifications with various expiration dates (some expired, some urgent, some current)

## Sample Data Structure

| Certification Name | Issuing Body | Expiration Date | Renewal Cost | CE Credits Required | CE Credits Completed |
|-------------------|--------------|----------------|--------------|-------------------|-------------------|
| Registered Nurse License | State Board | 2024-03-15 | $150 | 30 | 30 |
| BLS Certification | AHA | 2024-06-20 | $75 | 4 | 4 |
| ACLS Certification | AHA | 2024-01-10 | $180 | 8 | 5 |
| ... | ... | ... | ... | ... | ... |

## Required Actions

### 1. Add "Days Until Expiration" Calculation Column (Column G)
- Create formula: `=C2-TODAY()` (where C is Expiration Date column)
- Copy formula down for all certification rows
- Negative values indicate expired certifications

### 2. Create "Status" Categorization Column (Column H)
- Create nested IF formula: `=IF(G2<0,"EXPIRED",IF(G2<90,"URGENT",IF(G2<365,"CURRENT","FUTURE")))`
- Categories based on days remaining:
  - **EXPIRED**: Days < 0
  - **URGENT**: 0 ≤ Days < 90
  - **CURRENT**: 90 ≤ Days < 365
  - **FUTURE**: Days ≥ 365
- Copy formula down for all rows

### 3. Apply Conditional Formatting to Status Column
- Select Status column (H2:H[last_row])
- Format → Conditional Formatting → Condition
- Rule 1: If cell value = "URGENT" → Red background
- Rule 2: If cell value = "EXPIRED" → Dark red background
- This makes urgent items visually obvious

### 4. Calculate Total Renewal Costs
- Navigate to cell below last data row in Renewal Cost column (Column D)
- Create SUM formula: `=SUM(D2:D[last_row])`
- Format as currency
- This aggregates budget needed for all renewals

### 5. Add "CE Status" Comparison Column (Column I)
- Create comparison formula: `=IF(F2>=E2,"Complete","INCOMPLETE")`
- Compares CE Credits Completed (F) vs CE Credits Required (E)
- Identifies certifications where continuing education isn't finished

### 6. Apply Warning Formatting to CE Status
- Select CE Status column
- Apply conditional formatting: "INCOMPLETE" → Yellow background
- Highlights certifications with insufficient CE credits

### 7. Sort by Urgency (Earliest Expiration First)
- Select entire data range (A1:[last_column][last_row])
- Data → Sort
- Sort by "Days Until Expiration" (Column G), ascending order
- Places most urgent certifications at top of list

### 8. Final Verification
- Confirm red-highlighted URGENT and EXPIRED statuses
- Verify total renewal budget displays
- Check that sorting placed earliest expirations first
- Ensure CE Status warnings are visible

## Success Criteria

1. ✅ **Days Calculation**: Column with `=Expiration-TODAY()` formula exists
2. ✅ **Status Categorization**: Nested IF formula correctly assigns EXPIRED/URGENT/CURRENT/FUTURE
3. ✅ **Status Formatting**: Red background on URGENT, dark red on EXPIRED
4. ✅ **Total Cost**: SUM formula aggregates all renewal costs
5. ✅ **CE Status Check**: Comparison formula identifies incomplete CE credits
6. ✅ **CE Warning Format**: Yellow highlighting on INCOMPLETE CE status
7. ✅ **Sorted by Urgency**: Data sorted ascending by Days Until Expiration
8. ✅ **Data Integrity**: Rows stayed together during sort

**Pass Threshold**: 75% (6 out of 8 criteria must pass)

## Skills Tested

- Date function mastery (TODAY(), date arithmetic)
- Conditional logic (nested IF statements)
- Conditional formatting for visual alerts
- Financial aggregation (SUM with currency)
- Data comparison and validation logic
- Sorting with data integrity
- Professional workflow optimization

## Tips

- TODAY() function returns the current date
- Date arithmetic: Subtracting dates gives number of days
- Nested IF: `=IF(condition1, result1, IF(condition2, result2, else_result))`
- Conditional formatting: Format → Conditional Formatting → Condition
- Sort entire data range to keep rows together
- Currency format: Format → Cells → Currency
- Copy formulas: Select cell, Ctrl+C, select range, Ctrl+V

## Common Pitfalls

- Forgetting to copy formulas down to all rows
- Sorting only one column instead of entire data range (breaks row integrity)
- Using hardcoded values instead of formulas
- Not applying conditional formatting to entire column
- Incorrect IF logic for status categories