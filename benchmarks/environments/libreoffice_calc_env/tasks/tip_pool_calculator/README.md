# LibreOffice Calc Tip Pool Distribution Task (`tip_pool_calculator@1`)

## Overview

This task tests an agent's ability to perform fair financial calculations for tip pool distribution in a restaurant setting. The agent must calculate each staff member's share of pooled tips based on their hours worked, using formulas to ensure accuracy and transparency. This simulates a real-world scenario where service workers need quick, fair, and verifiable tip distribution at the end of a busy shift.

## Rationale

**Why this task is valuable:**
- **Real-world Financial Calculations:** Tests practical math skills used daily in service industries
- **Proportional Distribution Logic:** Requires understanding of percentage-based allocation
- **Multi-step Formula Chains:** Combines SUM, division, and multiplication in a logical workflow
- **Accuracy Under Pressure:** Simulates time-sensitive calculations where errors cause real disputes
- **Transparent Record-keeping:** Demonstrates importance of auditable financial calculations
- **Common Pain Point:** Addresses a genuine workflow frustration for restaurant workers
- **Ethical Computing:** Fair distribution calculations have real impact on people's livelihoods

**Skill Progression:** This task bridges basic arithmetic formulas with real-world financial modeling, requiring careful attention to calculation order and cell references.

## Skills Required

### A. Interaction Skills
- **Cell Navigation:** Move efficiently between data entry areas
- **Formula Entry:** Type formulas with correct syntax and cell references
- **Formula Copying:** Apply formulas across multiple rows/cells
- **Value Verification:** Cross-check intermediate results make logical sense
- **Save Operations:** Export the completed spreadsheet

### B. LibreOffice Calc Knowledge
- **SUM Function:** Total multiple values (tips from sources, hours worked)
- **Division Operations:** Calculate proportions and percentages
- **Multiplication Operations:** Apply percentages to totals
- **Cell References:** Use both absolute ($B$8) and relative (B2) references appropriately
- **Formula Order of Operations:** Understand calculation precedence
- **Number Formatting:** Ensure currency displays correctly

### C. Task-Specific Skills
- **Proportional Distribution Logic:** Understand fair-share calculation (individual/total × pool)
- **Financial Accuracy:** Recognize when numbers don't add up correctly
- **Multi-source Aggregation:** Combine values from different data sources
- **Percentage Calculation:** Convert ratios to meaningful proportions
- **Verification Instinct:** Check that total distributed equals total collected

## Task Steps

### 1. Scenario Understanding
- Examine the pre-filled spreadsheet with staff data
- Identify the data structure:
  - Rows 2-6: 5 staff members with names and hours worked
  - Row 8: Totals row (needs formulas)
  - Rows 11-13: Tip sources section
- Note which cells need formulas (currently empty)

### 2. Calculate Total Tips Collected
- Navigate to cell B13 (Total Tips)
- Enter formula: `=SUM(B11:B12)` or `=B11+B12`
- Verify the result is $599.50

### 3. Calculate Total Hours Worked
- Navigate to cell B8 (Total row, Hours column)
- Enter formula: `=SUM(B2:B6)`
- Verify the result is 31.5 hours

### 4. Calculate Each Person's Hour Percentage
- Navigate to cell C2 (Alice's % of Hours)
- Enter formula: `=B2/$B$8`
  - Note the `$` signs for absolute reference to B8
- Copy formula down to C3:C6 (select C2, Ctrl+C, select C3:C6, Ctrl+V)
- Verify percentages look reasonable (should sum to ~100%)

### 5. Calculate Each Person's Tip Share
- Navigate to cell D2 (Alice's Tip Share)
- Enter formula: `=C2*$B$13`
  - Note the `$` signs for absolute reference to B13
- Copy formula down to D3:D6
- Verify shares are proportional to hours worked

### 6. Optional Verification Formulas
- In B8, you can add: `=SUM(B2:B6)` for total hours
- In C8, you can add: `=SUM(C2:C6)` to verify percentages sum to ~1.0
- In D8, you can add: `=SUM(D2:D6)` to verify total equals B13

### 7. Sanity Check
- Person with most hours (Alice, 8.5) should get largest share (~$162)
- Person with fewest hours (Diana, 4.0) should get smallest share (~$76)
- All shares should be positive
- Sum of shares should equal total tips

### 8. Save File
- The post-task hook will automatically save as "tip_pool.ods"

## Verification Strategy

### Verification Approach
The verifier uses **multi-level mathematical validation**:

### A. Total Tips Calculation (16.7%)
- ✅ Contains SUM formula
- ✅ Result equals cash + credit tips (within $0.01)

### B. Total Hours Calculation (16.7%)
- ✅ Contains SUM formula
- ✅ Result equals sum of individual hours (within 0.01)

### C. Percentage Calculations (16.7%)
- ✅ Each cell has formula: hours / total_hours
- ✅ Uses absolute reference ($B$8)
- ✅ All percentages sum to ~1.0 (within 0.01)

### D. Tip Share Calculations (16.7%)
- ✅ Each cell has formula: percentage × total_tips
- ✅ Uses absolute reference ($B$13)
- ✅ Shares proportional to hours

### E. Conservation Law (16.7%)
- ✅ Sum of all shares ≈ total tips (within $0.50)

### F. Formula Presence (16.7%)
- ✅ Key cells contain formulas, not hardcoded values

**Pass Threshold:** 70% (4 out of 6 criteria)

## Expected Results

| Name   | Hours | % of Hours | Tip Share |
|--------|-------|------------|-----------|
| Alice  | 8.5   | ~0.270     | ~$161.75  |
| Bob    | 6.0   | ~0.190     | ~$114.00  |
| Carlos | 7.5   | ~0.238     | ~$142.86  |
| Diana  | 4.0   | ~0.127     | ~$76.19   |
| Emma   | 5.5   | ~0.175     | ~$104.76  |
| TOTAL  | 31.5  | ~1.0       | $599.50   |

**Tip Sources:**
- Cash: $287.50
- Credit: $312.00
- **Total: $599.50**

## Tips

- Use `$` for absolute references when a formula needs to always point to the same cell
- Without `$`, references are relative and will shift when copied
- Formula `=B2/$B$8` in C2 becomes `=B3/$B$8` when copied to C3
- Formula `=B2/B8` in C2 becomes `=B3/B9` when copied to C3 (wrong!)
- Press F2 to edit a formula and see which cells it references
- Use Ctrl+` (backtick) to toggle formula display mode