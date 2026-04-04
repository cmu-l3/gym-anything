# Grocery Price Comparison Task

**Difficulty**: 🟡 Medium  
**Skills**: Data cleaning, formula creation, conditional logic, comparative analysis  
**Duration**: 240 seconds  
**Steps**: ~15

## Objective

Process messy grocery receipt data from three stores, normalize prices across different package sizes, and create a shopping guide that identifies the cheapest source for each item. This task tests data cleaning, unit price calculations, cross-dataset comparison, and conditional logic.

## Task Description

The agent must:
1. Open a spreadsheet containing grocery data from three stores with inconsistent product naming
2. Standardize product names across stores (e.g., "Milk 1gal" → "Milk, Whole, 1 Gal")
3. Calculate unit prices for each store (price per ounce, pound, or count)
4. Identify the minimum price across all stores for each product
5. Generate shopping recommendations showing which store has the best price
6. Apply conditional formatting to highlight best prices
7. Calculate summary statistics (total potential savings, store comparison)

## Starting State

- LibreOffice Calc opens with grocery data from Store A, Store B, and Store C
- Data contains: Product names (inconsistent), Quantities, Prices
- ~20 common grocery items with varying package sizes and prices
- Some stores don't carry certain items (empty cells)

## Data Layout Example

| Store A Product | Store A Qty | Store A Price | Store B Product | Store B Qty | Store B Price | Store C Product | Store C Qty | Store C Price |
|-----------------|-------------|---------------|-----------------|-------------|---------------|-----------------|-------------|---------------|
| Milk 1gal       | 128         | 3.99          | MILK WHOLE 1GAL | 128         | 4.29          | milk, whole     | 128         | 3.79          |
| Eggs Dozen      | 12          | 2.89          | EGGS 12CT       | 12          | 3.19          | eggs, large     | 12          | 2.69          |

## Required Actions

1. **Data Cleaning**: Create standardized product name column
2. **Unit Price Calculation**: Add formulas for price per unit at each store (=Price/Quantity)
3. **Minimum Detection**: Use MIN() to find lowest unit price across stores
4. **Recommendation Logic**: Use IF() to identify which store has best price
5. **Conditional Formatting**: Highlight minimum prices in each row
6. **Summary Stats**: Calculate total savings potential and store win counts

## Success Criteria

1. ✅ **Product Names Standardized** (≥90% consistency)
2. ✅ **Unit Prices Calculated** (Valid formulas present)
3. ✅ **Minimum Identified** (MIN function correctly finds lowest)
4. ✅ **Recommendations Generated** (IF logic names cheapest store)
5. ✅ **Formatting Applied** (Conditional formatting highlights best prices)
6. ✅ **Summary Accurate** (Statistics correctly calculated)

**Pass Threshold**: 75% (4 out of 6 criteria)

## Skills Tested

- Data cleaning and standardization (text manipulation)
- Formula creation (arithmetic, MIN, IF functions)
- Cell references (relative and absolute)
- Conditional logic
- Conditional formatting
- Summary statistics
- Real-world data handling

## Tips

- Use Find & Replace (Ctrl+H) to standardize product names
- Unit price formula: =Price/Quantity
- MIN function syntax: =MIN(B2:D2)
- IF function for recommendations: =IF(B2=MIN(B2:D2),"Store A",IF(C2=MIN(B2:D2),"Store B","Store C"))
- Select price columns and apply conditional formatting (Format → Conditional Formatting)
- Handle empty cells (stores not carrying items) by leaving blank or using IFERROR()