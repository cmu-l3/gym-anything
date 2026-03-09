# Spreadsheet Version Comparison Task (`version_diff_highlighter@1`)

**Difficulty**: 🟡 Medium  
**Skills**: Data comparison, conditional logic, cell formatting, attention to detail  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Compare two versions of product pricing data and visually highlight the cells that have changed. This task simulates a common real-world frustration: receiving updated spreadsheets via email with no changelog and needing to manually identify differences to catch unauthorized or unexpected modifications.

## Task Description

The agent must:
1. Open a LibreOffice Calc spreadsheet containing two sheets: "Version 1" and "Version 2"
2. Compare corresponding cells between the two versions
3. Identify which cells in Version 2 differ from Version 1
4. Apply visual highlighting (background color) to changed cells in Version 2
5. Save the file

The data represents product pricing information with columns:
- Product ID
- Product Name  
- Category
- Unit Price
- Stock Quantity
- Last Updated

Between Version 1 and Version 2, there are 5-7 intentional changes:
- Price increases or decreases
- Quantity adjustments
- Product name corrections
- Category changes

## Expected Results

- Changed cells in Version 2 sheet have background color applied (yellow, red, orange, or any visible color)
- At least 80% of actual changes are correctly highlighted (Recall ≥ 0.80)
- At least 80% of highlighted cells are actual changes (Precision ≥ 0.80)
- Combined F1 score ≥ 0.80

## Verification Criteria

1. ✅ **High Recall**: ≥80% of changed cells are highlighted
2. ✅ **High Precision**: ≥80% of highlighted cells are actual changes
3. ✅ **Visual Highlighting**: Changed cells have visible formatting
4. ✅ **F1 Score**: ≥0.80 (harmonic mean of precision and recall)

**Pass Threshold**: 75% (requires F1 score ≥ 0.80)

## Skills Tested

- Systematic data comparison
- Formula-based difference detection (optional approach)
- Cell formatting application
- Attention to detail
- Multi-sheet navigation
- Visual communication of findings

## Suggested Approach

**Option 1: Manual Scanning**
- Navigate between sheets comparing cells visually
- Select and format cells that differ

**Option 2: Formula Helper Column**
- Create comparison formulas like `=IF(Version1!B2<>Version2!B2,"CHANGED","")`
- Use results to identify which cells changed
- Apply formatting to those cells

**Option 3: Conditional Formatting**
- Use Calc's conditional formatting with formulas
- Automatically highlight differences

## Tips

- Work systematically (row by row or column by column)
- Use sheet tabs at bottom to switch between versions
- Apply consistent highlighting (e.g., all yellow background)
- Double-check your work before saving
- Common differences include price changes and quantity adjustments

## Real-World Context

**Scenario**: You're a procurement manager who received an updated supplier quote. The supplier claims "just minor updates" but you need to verify exactly what changed before approving. Missing a price increase or quantity change could cost thousands of dollars.