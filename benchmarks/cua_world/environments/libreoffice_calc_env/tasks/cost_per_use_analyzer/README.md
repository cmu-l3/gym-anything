# Cost Per Use Analyzer Task

**Difficulty**: 🟡 Medium  
**Skills**: Advanced formulas, error handling, conditional logic, data sorting, conditional formatting  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Create a personal finance analysis spreadsheet that calculates the "cost per use" for various purchased items to determine their true value. Handle incomplete data gracefully, create error-resistant formulas, apply conditional formatting, and sort results to identify poor-value purchases.

## Task Description

The agent must:
1. Open a LibreOffice Calc spreadsheet with pre-populated item data (Item Name, Purchase Price, Times Used)
2. In column D (Cost Per Use), create formulas that divide Purchase Price by Times Used
3. Implement error handling for division by zero (items never used)
4. In column E (Value Assessment), create IF formulas that categorize items based on cost-per-use thresholds
5. Apply currency formatting to Price and Cost Per Use columns
6. Apply conditional formatting to Cost Per Use column (color scale or condition-based)
7. Sort data by Cost Per Use in descending order (highest cost-per-use first)
8. Save the file

## Starting Data

The spreadsheet contains 12 items with the following structure:

| Item Name | Purchase Price | Times Used |
|-----------|---------------|------------|
| Home Exercise Bike | 450 | 12 |
| Bread Maker | 89 | 3 |
| Running Shoes | 120 | 200 |
| Specialty Kitchen Knife | 180 | 450 |
| Gym Membership (annual) | 600 | 8 |
| Formal Suit | 400 | 2 |
| Power Drill | 85 | 45 |
| Yoga Mat | 35 | 180 |
| Streaming Service (annual) | 144 | 200 |
| Camping Tent | 280 | 0 |
| Coffee Maker | 120 | 730 |
| Instant Pot | 99 | 0 |

## Expected Results

### Column D (Cost Per Use):
- Formula structure: `=IFERROR(B2/C2, 99999)` or `=IF(C2=0, 99999, B2/C2)` or similar
- Never-used items (Times Used = 0) should show 99999 or similar large penalty value
- Used items should show calculated cost per use
- No #DIV/0! errors visible

### Column E (Value Assessment):
- Formula structure using nested IF statements:
  - "Excellent Value" if cost per use < $1.00
  - "Good Value" if cost per use < $5.00
  - "Poor Value" if cost per use < $20.00
  - "Waste" if cost per use >= $20.00 or never used

### Formatting:
- Columns B and D: Currency format ($)
- Column D: Conditional formatting with color scale (green=low, yellow=medium, red=high)

### Sorting:
- Entire data range sorted by Cost Per Use (column D) in descending order
- Highest cost-per-use items at the top

## Verification Criteria

1. ✅ **Formula Structure**: Cost-per-use formulas correctly divide price by usage with error handling (100%)
2. ✅ **Error Handling**: No #DIV/0! errors visible; zero-usage items handled gracefully (100%)
3. ✅ **Conditional Logic**: Value assessment formulas correctly categorize based on thresholds (100%)
4. ✅ **Proper Sorting**: Data sorted by cost-per-use in descending order (100%)
5. ✅ **Visual Enhancement**: Conditional formatting applied to cost-per-use column (100%)
6. ✅ **Number Formatting**: Currency formatting applied to appropriate columns (100%)

**Pass Threshold**: 70% (requires 4/6 criteria)

## Skills Tested

- Division formulas with error handling
- IFERROR or IF function usage
- Nested IF statements for categorization
- Data range sorting while preserving row integrity
- Conditional formatting application
- Currency number formatting
- Real-world data quality management

## Tips

- Use `=IFERROR(B2/C2, 99999)` to handle division by zero
- Alternatively, use `=IF(C2=0, 99999, B2/C2)`
- For Value Assessment, use nested IF: `=IF(D2>=20, "Waste", IF(D2>=5, "Poor Value", IF(D2>=1, "Good Value", "Excellent Value")))`
- Select entire data range (including headers) before sorting
- Use Data → Sort, sort by Cost Per Use column, descending order
- Conditional formatting: Format → Conditional Formatting → Color Scale
- Currency formatting: Select column → Format → Cells → Currency

## Real-World Context

This task represents a common personal finance analysis where people:
- Review past purchases to identify wasteful spending
- Use cost-per-use metrics to justify or regret expensive purchases
- Make decisions about decluttering or future purchase priorities
- Handle incomplete data (items still in boxes, never-used gym equipment)