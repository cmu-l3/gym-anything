# LibreOffice Calc Community Tool Library Overdue Tracker Task (`tool_library_overdue@1`)

## Overview

This task challenges an agent to work with date calculations, conditional logic, and multi-step formulas to identify overdue items in a community tool library and calculate associated late fees. The agent must understand date arithmetic (TODAY() function, date differences), apply conditional logic (IF statements), perform calculations based on conditions, and flag urgent situations. This represents a realistic workflow where community organizations track borrowed items and need to identify problems requiring intervention.

## Rationale

**Why this task is valuable:**
- **Date Function Mastery:** Introduces critical DATE functions (TODAY(), date arithmetic) essential for scheduling and tracking
- **Conditional Logic Application:** Tests multi-level IF statements and nested conditions for real decision-making
- **Real-world Problem Solving:** Represents actual community organization workflows (tool libraries, seed exchanges, "Library of Things")
- **Data State Analysis:** Works with items in different states (returned, checked out, overdue, urgent)
- **Arithmetic with Conditions:** Calculates fees only when conditions are met
- **Deadline Management Skills:** Universal skill applicable to invoicing, project management, subscription tracking

**Skill Progression:** This task combines intermediate formula complexity with practical date handling, bridging basic calculations and advanced conditional logic.

## Task Description

The agent must:
1. Open the tool library spreadsheet with checkout data
2. Add a "Days Overdue" column (F) that calculates days past due date for unreturned items
3. Add a "Late Fee" column (G) that calculates $1.00 per day overdue
4. Add a "Status" column (H) that flags items as URGENT (7+ days), Overdue (1-6 days), On Time, or Returned
5. Ensure formulas handle edge cases correctly (returned items, items not yet due)

## Expected Results

- **Column F (Days Overdue)**: Formula using TODAY(), checking for empty Return Date, calculating date difference
- **Column G (Late Fee)**: Formula multiplying days overdue by $1.00
- **Column H (Status)**: Formula with nested IF statements for status classification
- **Returned items**: Show 0 days overdue and $0.00 fees
- **Overdue items**: Show correct calculations based on current date
- **URGENT items**: Items 7+ days overdue flagged appropriately

## Verification Criteria

1. ✅ **Days Overdue Formula Present**: Column F contains formulas with TODAY() function
2. ✅ **Conditional Logic Correct**: Formulas check for empty Return Date
3. ✅ **Overdue Calculations Accurate**: Days overdue calculated correctly for test items
4. ✅ **Late Fees Correct**: Fees match days overdue × $1.00
5. ✅ **Status Logic Valid**: URGENT/Overdue/On Time/Returned correctly assigned
6. ✅ **Edge Cases Handled**: Returned items show 0, items not yet due show 0

**Pass Threshold**: 70% (requires working date calculations with mostly correct logic)

## Skills Tested

- DATE functions (TODAY(), date arithmetic)
- IF function with nested conditions
- Conditional calculations
- Empty cell checking
- Formula copying across rows
- Date comparison operators
- Multi-criteria logic

## Data Structure

The spreadsheet contains:
- **Column A**: Item Name (tools like "Power Drill", "Chainsaw")
- **Column B**: Borrower Name
- **Column C**: Checkout Date
- **Column D**: Due Date
- **Column E**: Return Date (empty if still checked out)
- **Column F**: Days Overdue (to be calculated)
- **Column G**: Late Fee (to be calculated)
- **Column H**: Status (to be calculated)

## Tips

- Use TODAY() function to get current date
- Check if Return Date is empty: `E2=""`
- Calculate days difference: `TODAY() - D2`
- Use MAX(0, ...) to prevent negative days
- Nest IF statements for multi-level logic
- Copy formulas down to apply to all rows