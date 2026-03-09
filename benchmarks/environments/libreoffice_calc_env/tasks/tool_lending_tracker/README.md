# Tool Lending Tracker Task

**Difficulty**: 🟡 Medium  
**Skills**: Date calculations, conditional formulas, conditional formatting, data management  
**Duration**: 150 seconds  
**Steps**: ~15

## Objective

Manage a personal tool lending library by calculating loan durations, identifying overdue items, and applying conditional formatting to highlight problematic loans. This task tests date arithmetic, IF statements, and visual data management through conditional formatting.

## Task Description

You are tracking tools you've lent to friends and neighbors. You need to:
1. Calculate how many days each tool has been out (using TODAY() function)
2. Create a status indicator showing "OVERDUE" for tools out >30 days, "OK" otherwise
3. Apply conditional formatting to visually highlight overdue items in red
4. Save the completed spreadsheet

## Starting State

A CSV file opens in LibreOffice Calc with the following columns:
- **Tool Name**: Name of the tool (Power Drill, Ladder, etc.)
- **Borrower**: Person who borrowed the tool
- **Date Lent**: Date the tool was lent (various dates)
- **Expected Return**: Expected return date
- **Value**: Tool value in dollars

## Required Actions

### 1. Add "Days Out" Calculation Column (Column E)
- Click on cell E1 and type header: "Days Out"
- In cell E2, create formula: `=TODAY()-C2`
- Copy formula down to all data rows (E3, E4, E5, etc.)

### 2. Add "Status" Column with Conditional Logic (Column F)
- Click on cell F1 and type header: "Status"
- In cell F2, create IF formula: `=IF(E2>30,"OVERDUE","OK")`
- Copy formula down to all data rows

### 3. Apply Conditional Formatting
- Select the Status column cells with data (F2:F[last row])
- Navigate to: Format → Conditional Formatting → Condition...
- Set condition: Cell value is equal to "OVERDUE"
- Choose red background or red text color
- Click OK to apply

### 4. Save the File
- Press Ctrl+S to save
- File will be exported as ODS format

## Expected Results

- **Column E (Days Out)**: Contains formulas calculating days since tool was lent
- **Column F (Status)**: Contains IF formulas showing "OVERDUE" or "OK"
- **Conditional Formatting**: Cells with "OVERDUE" are highlighted in red
- **Calculations**: At least one tool should be correctly identified as overdue

## Verification Criteria

1. ✅ **Days Out Formula**: Column E contains `=TODAY()-[DateLent]` formula for all data rows
2. ✅ **Status Formula**: Column F contains `=IF([DaysOut]>30,"OVERDUE","OK")` formula for all data rows
3. ✅ **Correct Calculations**: At least one row correctly shows OVERDUE status
4. ✅ **Conditional Formatting**: OVERDUE cells have distinct visual formatting
5. ✅ **Formula Propagation**: Formulas applied to all data rows

**Pass Threshold**: 80% (4/5 criteria must pass)

## Skills Tested

- Date arithmetic with TODAY() function
- Conditional logic with IF statements
- Formula creation and copying
- Conditional formatting configuration
- Cell range selection
- Menu navigation (Format menu)
- Real-world data management

## Tips

- Use TODAY() function for current date (not a hardcoded date)
- The IF function syntax is: =IF(condition, value_if_true, value_if_false)
- To copy formulas down: Select cell, Ctrl+C, select range, Ctrl+V
- Or use fill down: Select E2, then drag the small square at bottom-right corner down
- Conditional formatting requires exact text match: "OVERDUE" (case-sensitive)
- You can test formulas by checking if cells with >30 days show "OVERDUE"

## Real-World Context

This spreadsheet solves the common problem of tracking lent items and forgetting who has what. By calculating loan duration and highlighting overdue items, you can easily identify which friends to contact about returning tools. This workflow applies to tracking library books, borrowed money, or any time-sensitive loans.