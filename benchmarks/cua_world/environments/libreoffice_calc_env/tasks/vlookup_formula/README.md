# VLOOKUP Formula Task

**Difficulty**: 🟡 Medium
**Estimated Steps**: 60
**Timeout**: 240 seconds (4 minutes)

## Objective

Use VLOOKUP formulas to populate product prices in the Orders sheet by looking up product IDs from the Products sheet. This task tests advanced formula skills and multi-sheet references.

## Starting State

- LibreOffice Calc opens with a workbook containing two sheets
- **Products sheet**: Product ID and Price columns
- **Orders sheet**: Order ID and Product ID columns (prices missing)

## Data Layout

### Products Sheet
| Product ID | Price  |
|------------|--------|
| P001       | 29.99  |
| P002       | 49.99  |
| P003       | 15.99  |
| P004       | 89.99  |
| P005       | 12.50  |

### Orders Sheet (Before)
| Order ID | Product ID | Price |
|----------|------------|-------|
| O001     | P002       | ?     |
| O002     | P001       | ?     |
| O003     | P004       | ?     |
| O004     | P003       | ?     |
| O005     | P005       | ?     |

## Required Actions

1. Navigate to the Orders sheet
2. Click on the first Price cell (C2)
3. Enter VLOOKUP formula: \`=VLOOKUP(B2,Products.A:B,2,FALSE)\`
   - B2: The Product ID to look up
   - Products.A:B: The lookup table (Products sheet, columns A and B)
   - 2: Return value from column 2 (Price)
   - FALSE: Exact match
4. Copy the formula down to fill all price cells
5. Save the file

## Expected Result After VLOOKUP

### Orders Sheet (After)
| Order ID | Product ID | Price  |
|----------|------------|--------|
| O001     | P002       | 49.99  |
| O002     | P001       | 29.99  |
| O003     | P004       | 89.99  |
| O004     | P003       | 15.99  |
| O005     | P005       | 12.50  |

## Success Criteria

1. ✅ VLOOKUP formulas found (at least 3 out of 5 cells)
2. ✅ Prices correct (at least 3 out of 5 match expected values)
3. ✅ Formula uses correct sheet reference (references Products sheet)

**Pass Threshold**: 66% (2 out of 3 criteria)

## Skills Tested

- VLOOKUP function syntax
- Multi-sheet references
- Relative vs absolute cell references
- Formula copying and auto-fill
- Lookup table understanding
- Error handling (#N/A errors)

## VLOOKUP Syntax

\`\`\`
=VLOOKUP(lookup_value, table_array, column_index, [range_lookup])
\`\`\`

- **lookup_value**: What to search for (Product ID)
- **table_array**: Where to search (Products sheet)
- **column_index**: Which column to return (2 for Price)
- **range_lookup**: FALSE for exact match, TRUE for approximate

## Tips

- Sheet references use format: \`SheetName.CellRange\`
- Use absolute references ($) if needed: \`Products.$A:$B\`
- VLOOKUP searches the first column of the table
- The value to return must be to the right of the lookup column
- Copy formulas by selecting cell and dragging fill handle
- Check for #N/A errors - they indicate lookup failures
