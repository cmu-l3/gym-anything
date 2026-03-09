# Estate Sale Profit Calculator Task

**Difficulty**: 🟡 Medium  
**Skills**: Data cleaning, conditional formulas, text parsing, financial analysis  
**Duration**: 300 seconds  
**Steps**: ~25

## Objective

Clean up a messy estate sale inventory spreadsheet and calculate whether the sale reached its $2,000 financial goal. This task tests real-world data cleaning skills, conditional logic, text parsing, and business calculation abilities.

## Context

Maria inherited her aunt's house and held an estate sale this weekend. Her sister helped track sales on a spreadsheet, but they were too busy with customers to enter data consistently. Now Maria needs to know if she made the $2,000 needed for the moving truck deposit, and she needs this answer quickly to confirm with the moving company tomorrow morning.

## Task Description

The agent must:
1. Open the messy estate sale inventory CSV file
2. Analyze inconsistent data in Status and Notes columns
3. Create a calculated column for "Actual Sale Price" using formulas
4. Handle variations: "SOLD", "sold", "Sold to X", empty cells
5. Extract sale prices from text like "SOLD $45", "sold for 50", etc.
6. Calculate total revenue from sold items
7. Compare against the $2,000 goal
8. Determine if target was met and by how much
9. Save the cleaned spreadsheet

## Starting Data Structure

**Columns:**
- **Item**: Description of the item being sold
- **Asking Price**: Original price tag amount
- **Status**: "SOLD", "sold", "Available", or blank (inconsistent!)
- **Notes**: Mixed information - sale prices, buyer names, or empty

**Example rows:**