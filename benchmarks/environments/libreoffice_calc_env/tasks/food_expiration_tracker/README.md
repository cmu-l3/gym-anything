# Food Expiration Tracker Task

**Difficulty**: 🟡 Medium  
**Skills**: Date formulas, conditional formatting, data sorting, TODAY() function  
**Duration**: 180 seconds  
**Steps**: ~50

## Objective

Transform a basic food inventory list into an actionable expiration tracking system. The agent must calculate expiration dates, determine urgency using the TODAY() function, apply visual highlighting to items expiring soon, and sort the inventory by urgency.

## Task Description

The agent must:
1. Open a spreadsheet with food inventory data (Item, Category, Purchase Date, Shelf Life Days)
2. Calculate Expiration Dates in column E using formula: `=C[row]+D[row]`
3. Calculate Days Until Expiration in column F using formula: `=E[row]-TODAY()`
4. Apply conditional formatting to column F to highlight cells with values ≤7 (expiring soon)
5. Sort the entire data range by column F (Days Until Expiration) in ascending order
6. Save the file

## Starting Data Structure

| A: Item Name | B: Category | C: Purchase Date | D: Shelf Life Days | E: Expiration Date | F: Days Until Expiration |
|--------------|-------------|------------------|--------------------|--------------------|--------------------------|
| Milk         | Dairy       | 2024-12-10       | 7                  | (empty)            | (empty)                  |
| Canned Beans | Canned      | 2024-01-01       | 730                | (empty)            | (empty)                  |
| ...          | ...         | ...              | ...                | (empty)            | (empty)                  |

## Expected Results

- **Column E (Expiration Date)**: Formulas calculating Purchase Date + Shelf Life Days
- **Column F (Days Until Expiration)**: Formulas calculating Expiration Date - TODAY()
- **Conditional Formatting**: Column F cells with values ≤7 highlighted (bold/colored)
- **Sorted Data**: Rows sorted ascending by column F (most urgent items first)
- **Data Integrity**: All row relationships preserved (item names match their dates/categories)

## Verification Criteria

1. ✅ **Expiration Date Formulas**: Column E contains correct formulas (C+D pattern)
2. ✅ **Days Until Formulas**: Column F contains TODAY() function (E-TODAY() pattern)
3. ✅ **Conditional Formatting**: Formatting rule applied to column F for values ≤7
4. ✅ **Proper Sorting**: Data sorted ascending by Days Until Expiration
5. ✅ **Formula Integrity**: Formulas still calculate correctly after sorting
6. ✅ **Data Integrity**: Row data relationships preserved after sorting

**Pass Threshold**: 75% (at least 4-5 out of 6 criteria must pass)

## Skills Tested

- Date arithmetic and DATE functions
- TODAY() function for dynamic calculations
- Formula creation and copying
- Conditional formatting with numeric conditions
- Data sorting while preserving row integrity
- Understanding of relative cell references

## Real-World Context

This task simulates a common household problem: reducing food waste by tracking expiration dates. The spreadsheet transforms raw purchase data into actionable insights about what needs to be used soon, potentially saving hundreds of dollars per year in wasted food.

## Tips

- Use `=C2+D2` to calculate expiration dates (date + days)
- Use `=E2-TODAY()` for days until expiration (will update daily)
- Conditional formatting: Format → Conditional Formatting → Condition
  - Set condition: "Cell value is less than or equal to" 7
  - Apply formatting: Bold, red/orange background
- Sort: Select all data (A1:F21), then Data → Sort, choose column F, ascending
- Ensure "Range contains column labels" is checked when sorting