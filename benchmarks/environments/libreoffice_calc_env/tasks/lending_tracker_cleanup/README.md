# Personal Lending Tracker Cleanup Task

**Difficulty**: 🟡 Medium  
**Skills**: Date functions, conditional logic, SUMIF, conditional formatting  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Clean up a messy personal lending log to identify unreturned items and calculate total value at risk. This task tests date calculations, conditional formulas, SUMIF logic, and visual formatting in a realistic scenario.

## Task Description

You've been informally lending books, tools, and equipment to friends and neighbors but your tracking has gotten inconsistent. Some items were returned and logged, others are still out there. Before moving to a new place, you need to:

1. Calculate how long each unreturned item has been on loan
2. Identify what's currently outstanding (no return date)
3. Calculate total value of unreturned items
4. Visually highlight items out longer than 30 days

## Starting State

- LibreOffice Calc opens with your partial lending log
- Columns: Item Name (A), Borrowed By (B), Lent Date (C), Return Date (D), Estimated Value (E)
- Some Return Date cells are empty (items still on loan)
- Mix of recent and old lending dates
- 10 items total, some returned, some still out

## Sample Data

| Item Name          | Borrowed By    | Lent Date   | Return Date | Est. Value |
|--------------------|----------------|-------------|-------------|------------|
| Circular Saw       | Tom Martinez   | 2024-09-15  |             | $120       |
| "Educated" book    | Sarah Chen     | 2024-11-20  | 2024-12-05  | $18        |
| Pressure Washer    | Mike Johnson   | 2024-08-01  |             | $200       |
| Camping Tent       | Lisa Park      | 2024-12-10  | 2024-12-18  | $150       |
| ... (more rows)    |                |             |             |            |

## Required Actions

### 1. Add "Days On Loan" Column
- In column F, add header "Days On Loan"
- Create formula: `=IF(ISBLANK(D2), TODAY()-C2, "")`
  - This calculates days for unreturned items only
  - Alternative: `=IF(D2="", TODAY()-C2, "")` may work depending on blank format
- Copy formula to all data rows (F2:F11 or similar)

### 2. Calculate Total Value Outstanding
- Find a cell below your data (e.g., E13 or similar)
- Add label "Total Outstanding:" in adjacent cell
- Create SUMIF formula: `=SUMIF(D:D, "", E:E)`
  - Sums Estimated Value where Return Date is blank
  - Alternative: `=SUMIF(D2:D11, "", E2:E11)` with specific range

### 3. Apply Conditional Formatting
- Select Days On Loan column (F2:F11)
- Format → Conditional Formatting → Condition
- Rule: "Cell value is greater than 30"
- Format: Red background or bold red text
- This highlights items out more than 30 days

### 4. Optional Enhancements
- Sort by Days On Loan (descending) to prioritize follow-ups
- Add Status column with "OUT" or "Returned"

## Success Criteria

1. ✅ **Days Calculation Formula** (40%): Column F contains proper formula with TODAY(), IF, and ISBLANK
2. ✅ **Total Value Formula** (30%): SUMIF formula correctly calculates value of unreturned items
3. ✅ **Conditional Formatting** (20%): Visual highlighting applied to items out >30 days
4. ✅ **Formula Coverage** (10%): Formulas applied to all data rows, not just first few

**Pass Threshold**: 75% (requires at least 3 out of 4 criteria)

## Skills Tested

- Date arithmetic and TODAY() function
- Conditional logic (IF, ISBLANK)
- SUMIF with blank cell conditions
- Conditional formatting rules
- Understanding business logic (lending workflow)
- Working with partially complete data

## Expected Formulas

**Days On Loan (F2):**