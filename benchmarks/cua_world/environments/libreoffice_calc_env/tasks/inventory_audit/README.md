# Inventory Audit Reconciliation Task

**Difficulty**: 🟡 Medium
**Estimated Steps**: 25
**Timeout**: 240 seconds (4 minutes)

## Objective

Help a retail store manager reconcile inventory discrepancies by calculating differences between expected and actual stock counts, computing financial impacts, and highlighting problematic items with conditional formatting. This represents a real business workflow where inventory accuracy directly impacts ordering decisions.

## Scenario

A store manager arrives Monday morning after a weekend physical inventory count. The spreadsheet shows 45 items with system-expected quantities vs. actual physical counts. Some items are missing (potential theft or miscounts), some show overages (counting errors), and some match perfectly. The manager needs to:
- Quickly identify which items have discrepancies
- Calculate the financial impact of each discrepancy
- Prioritize which items need immediate investigation

## Starting State

- LibreOffice Calc opens with pre-populated inventory data
- **Column A:** Product Name (45 retail items)
- **Column B:** Expected Qty (system inventory count)
- **Column C:** Actual Count (physical inventory count)
- **Column D:** Unit Price (dollar value per item)
- **Column E:** Difference (empty - needs formula)
- **Column F:** Value Impact (empty - needs formula)

## Required Actions

### Step 1: Calculate Quantity Differences
1. Click on cell E2 (first data row in Difference column)
2. Enter formula: `=C2-B2` (Actual minus Expected)
3. Copy formula down to all inventory items (E2:E46)

### Step 2: Calculate Financial Impact
1. Click on cell F2 (first data row in Value Impact column)
2. Enter formula: `=E2*D2` (Difference times Unit Price)
3. Copy formula down to all items (F2:F46)

### Step 3: Apply Conditional Formatting to Differences
1. Select the Difference column range (E2:E46)
2. Navigate to `Format → Conditional Formatting → Condition...`
3. Create rules:
   - If cell value < 0, apply red background (shortages are critical)
   - If cell value > 0, apply yellow/orange background (overages need investigation)

### Step 4: Apply Conditional Formatting to Value Impact
1. Select the Value Impact column range (F2:F46)
2. Navigate to `Format → Conditional Formatting → Condition...`
3. Create rule for high-value discrepancies (e.g., < -50) with distinct formatting

### Step 5: Save the File
- The file will be automatically saved as `inventory_reconciliation.ods`

## Success Criteria

1. ✅ **Difference Formulas Present**: Column E contains formulas calculating (Actual - Expected)
2. ✅ **Value Impact Formulas Present**: Column F contains formulas calculating (Difference × Unit Price)
3. ✅ **Formulas in All Rows**: Formulas exist in at least 80% of data rows
4. ✅ **Conditional Formatting Applied**: Difference column has conditional formatting rules
5. ✅ **Color-Based Highlighting**: Formatting uses background colors for positive/negative values
6. ✅ **Mathematical Accuracy**: Spot-check shows correct calculations

**Pass Threshold**: 70% (requires substantial progress on both formulas and formatting)

## Skills Tested

- Formula creation with arithmetic operators
- Relative cell references
- Formula copying across ranges
- Conditional formatting navigation
- Rule-based formatting configuration
- Business logic understanding
- Data analysis and visualization

## Expected Results

After completion:
- Column E shows differences: negative numbers (shortages), positive numbers (overages), zeros (matches)
- Column F shows dollar impact of each discrepancy
- Red highlighting on shortage items (negative differences)
- Yellow/orange highlighting on overage items (positive differences)
- High-value discrepancies are visually prominent

## Tips

- Use relative cell references (e.g., C2-B2) not absolute ($C$2-$B$2) for easy copying
- Select the cell with formula, then Ctrl+C and select range, Ctrl+V to copy formulas
- Conditional formatting: Format → Conditional Formatting → Condition...
- For conditions, use "Cell value is less than 0" and "Cell value is greater than 0"
- Choose distinct colors (red for problems, yellow/green for information)
- Verify formulas copied correctly by clicking different cells and checking formula bar

## Real-World Context

This task mirrors actual retail operations where:
- Physical inventory counts happen monthly/quarterly
- Discrepancies represent real financial loss (theft, spoilage, errors)
- Managers need quick visual identification of problem areas
- High-value discrepancies require immediate investigation
- Reports must be prepared quickly for restocking orders