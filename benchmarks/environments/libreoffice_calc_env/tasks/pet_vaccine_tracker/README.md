# Pet Vaccination Tracker Task

**Difficulty**: 🟡 Medium  
**Skills**: Date formulas, IF logic, conditional formatting, data organization  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Organize scattered pet vaccination records into a functional tracking system that automatically calculates when booster shots are due and visually highlights overdue vaccinations. This task tests date arithmetic, logical formulas, and conditional formatting skills.

## Task Description

The agent must:
1. Open a partially completed vaccination tracker spreadsheet
2. Add formulas to calculate "Next Due Date" based on last vaccination date + interval
3. Create IF formulas to determine vaccine "Status" (Current vs OVERDUE)
4. Apply conditional formatting to highlight overdue vaccines in red
5. Save the completed tracker

## Real-World Context

Alex has three pets (Max, Bella, and Whiskers) and needs to organize vaccination records for an upcoming boarding reservation. The new vet clinic requires up-to-date documentation, and Alex needs to quickly identify which vaccines are overdue and when boosters are needed.

## Data Structure

| Pet Name | Vaccine Type | Last Vaccination | Interval (years) | Next Due Date | Status |
|----------|--------------|------------------|------------------|---------------|--------|
| Max      | Rabies       | 2021-03-15      | 3                | [EMPTY]       | [EMPTY] |
| Bella    | DHPP         | 2023-06-20      | 3                | [EMPTY]       | [EMPTY] |
| ...      | ...          | ...             | ...              | [EMPTY]       | [EMPTY] |

## Expected Results

- **Column E (Next Due Date)**: Contains formulas that add interval (in days) to last vaccination date
  - Example: `=C2+(D2*365)` or `=DATE(YEAR(C2)+D2,MONTH(C2),DAY(C2))`
- **Column F (Status)**: Contains IF formulas comparing next due date to TODAY()
  - Example: `=IF(E2<TODAY(),"OVERDUE","Current")`
- **Conditional Formatting**: Cells with "OVERDUE" status highlighted in red

## Verification Criteria

1. ✅ **Next Due Formulas Present**: Column E contains formulas (not hardcoded dates) for 80%+ of data rows
2. ✅ **Date Calculations Correct**: Next due dates are 1-3 years after last vaccination dates
3. ✅ **Status Formulas Present**: Column F contains IF formulas with TODAY() function
4. ✅ **Overdue Logic Correct**: Status shows "OVERDUE" when next due date < current date
5. ✅ **Conditional Formatting Applied**: OVERDUE cells have red background
6. ✅ **Data Integrity**: Original pet names and vaccination dates unchanged

**Pass Threshold**: 70% (4/6 criteria must pass)

## Skills Tested

- Date arithmetic and DATE functions
- IF logical functions
- TODAY() function for current date
- Conditional formatting with color rules
- Formula copying and cell references
- Data validation and verification

## Tips

- Use `=C2+(D2*365)` to add years as days to a date
- Alternative: `=DATE(YEAR(C2)+D2,MONTH(C2),DAY(C2))` for date arithmetic
- IF formula: `=IF(E2<TODAY(),"OVERDUE","Current")`
- Conditional Formatting: Format → Conditional Formatting → Condition
- Set rule: Cell value equal to "OVERDUE" → Red background
- Copy formulas down using Ctrl+D or fill handle