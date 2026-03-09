# Formula Error Detective Task

**Difficulty**: 🟡 Medium  
**Skills**: Formula debugging, error diagnosis, cell reference repair  
**Duration**: 240 seconds  
**Steps**: ~20

## Objective

Systematically diagnose and repair broken formulas in a spreadsheet damaged during collaborative editing. The file contains cascading errors (#REF!, #NAME?, #VALUE!) from moved cells, renamed sheets, and deleted rows. You must identify all broken formulas, understand their original intent, and fix them to restore functionality.

## Realistic Scenario

**Context:** You're a financial analyst. Your manager reorganized your quarterly expense tracking spreadsheet for a presentation—moving rows/columns, renaming sheets, deleting "duplicates." They've returned it saying, "Something's wrong with the numbers—can you fix this before the 2pm meeting?"

**User Frustration:** "I can't believe they just moved things without checking! Now I have to debug this under time pressure."

## Task Description

When you open the file, you'll see:
- **#REF!** errors in the Summary sheet (invalid cell references)
- **#NAME?** errors (unrecognized sheet names)
- **#VALUE!** errors (wrong data types in formulas)

The spreadsheet has two sheets:
1. **Expenses** sheet: Monthly expense entries (Date, Category, Amount, Notes)
2. **Summary** sheet: Totals by category using formulas that reference Expenses

## Required Actions

1. **Assess damage**: Identify all cells with formula errors
2. **Diagnose #REF! errors**: Find what cells were moved/deleted and where they are now
3. **Diagnose #NAME? errors**: Check if sheets were renamed
4. **Diagnose #VALUE! errors**: Find if text got mixed into numeric ranges
5. **Repair systematically**: Fix formulas to point to correct cell ranges
6. **Verify**: Ensure totals make sense and all errors eliminated
7. **Save**: File → Save (or Ctrl+S)

## Expected Results

- **Zero error codes** (#REF!, #NAME?, #VALUE!, etc.)
- **Working formulas** in Summary sheet (not hardcoded values)
- **Accurate calculations** that match source data
- **Data preserved** (no accidental deletions during repair)

## Verification Criteria

1. ✅ **All Errors Eliminated**: No cells contain #REF!, #NAME?, #VALUE!, or other error codes
2. ✅ **Formulas Present**: Summary cells contain formulas, not hardcoded numbers
3. ✅ **Accurate Calculations**: Totals match expected values from source data (±$0.01)
4. ✅ **Cross-Sheet References Valid**: Formulas correctly reference the Expenses sheet
5. ✅ **Data Preserved**: Original expense entries still exist

**Pass Threshold**: 75% (4/5 criteria must pass)

## Skills Tested

- **Error Recognition**: Distinguish #REF!, #NAME?, #VALUE! error types
- **Formula Inspection**: View and edit formulas in formula bar
- **Diagnostic Reasoning**: Infer original formula from context
- **Cell Navigation**: Jump between sheets and referenced cells
- **Systematic Problem Solving**: Fix errors in logical order (source → dependents)
- **Validation**: Verify repairs produce sensible results

## Common Broken Formula Patterns

### Before (Working):