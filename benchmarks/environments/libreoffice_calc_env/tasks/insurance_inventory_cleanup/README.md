# Home Inventory Insurance Documentation Task

**Difficulty**: 🟡 Medium  
**Skills**: Data cleaning, text standardization, formula creation, conditional formatting, data validation  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Clean and organize messy home inventory data collected hastily after a kitchen fire scare. Transform inconsistent, incomplete data into a properly formatted insurance inventory with standardized categories, calculated depreciated values, and flagged items needing additional documentation.

## Scenario

A homeowner experienced a kitchen fire scare (quickly extinguished but frightening) and was reminded by their insurance agent to document all belongings for claims. They frantically collected data over several days using their phone, old receipts, and rough estimates—resulting in inconsistent formatting, mixed date formats, unclear categories, and incomplete information.

## Task Description

The agent must:
1. Open the messy inventory spreadsheet (provided)
2. Standardize inconsistent category names (Electronics vs electronic vs ELECTRONICS)
3. Normalize mixed date formats ("3 years ago", "2021", "Jan 2020", etc.)
4. Calculate item age from purchase dates
5. Apply category-specific depreciation formulas to estimate current values
6. Flag high-value items needing photos or receipts
7. Apply conditional formatting to highlight important items
8. Calculate summary statistics by category and room
9. Save the cleaned file

## Data Issues to Fix

### Category Inconsistencies
- "Electronics" / "electronic" / "ELECTRONICS" → standardize to "Electronics"
- "Furniture" / "furniture " / "Furnature" → standardize to "Furniture"  
- "Appliance" / "appliances" / "Appliances" → standardize to "Appliances"
- "Jewelry" / "jewlery" / "JEWELRY" → standardize to "Jewelry"
- "Tools" / "tools" / "tool" → standardize to "Tools"

### Date Format Variations
- "3 years ago" → calculate actual date
- "2021" → assume mid-year (2021-06-01)
- "Jan 2020" → convert to 2020-01-01
- Mixed formats: "3/15/2022", "15-Mar-2022" → standardize to YYYY-MM-DD

### Missing Data
- Some items lack purchase dates or prices
- Notes column has incomplete documentation status

## Required Calculations

### Depreciation Rates (per year)
- **Electronics**: 20% per year (max 80% depreciation)
- **Furniture**: 10% per year (max 50% depreciation)
- **Appliances**: 15% per year (max 70% depreciation)
- **Jewelry**: 0% (retains value)
- **Tools**: 8% per year (max 40% depreciation)

### Formula Example