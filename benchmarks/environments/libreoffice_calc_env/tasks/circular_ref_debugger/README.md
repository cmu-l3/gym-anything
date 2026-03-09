# Circular Reference Debugger Task

**Difficulty**: 🟡 Medium  
**Skills**: Formula debugging, circular reference resolution, dependency analysis  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Diagnose and fix circular reference errors in a broken budget spreadsheet. The agent must identify formulas that reference each other in a loop, understand the intended calculation logic, and restructure the formulas to break the circular dependency while preserving correct calculations.

## Task Description

You've inherited a Q4 departmental budget spreadsheet that shows circular reference errors and won't calculate totals correctly. The budget review meeting is this afternoon, and you need accurate numbers.

**The Problem:**
- Overhead expenses are calculated as 15% of Net Income
- Net Income depends on Total Expenses
- Total Expenses includes Overhead
- This creates a circular loop: Overhead → Net Income → Total Expenses → Overhead

**Your Goal:**
1. Identify the circular reference
2. Understand the intended logic
3. Fix the formulas to break the circular dependency
4. Ensure calculations are correct
5. Verify the Grand Total is accurate

## Expected Results

After fixing the circular reference:
- **No circular reference warnings** when opening the file
- **No #REF! errors** in any cells
- **Formulas preserved** (not just hard-coded values)
- **Grand Total (B15)** = $45,750.00 (Net Income)
- **All calculations working** correctly

## Verification Criteria

1. ✅ **No Circular References**: Spreadsheet loads without circular reference warnings
2. ✅ **No Formula Errors**: No cells contain #REF!, #VALUE!, or other error codes
3. ✅ **Formulas Present**: Key cells still contain formulas (not hard-coded values)
4. ✅ **Correct Grand Total**: Cell B15 equals $45,750.00 (±$1 tolerance)
5. ✅ **Clean Dependency Graph**: No cycles detected in cell reference graph
6. ✅ **Recalculation Works**: Formulas update correctly when inputs change

**Pass Threshold**: 80% (5/6 criteria must pass)

## Initial Spreadsheet Structure
