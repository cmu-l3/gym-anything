# Photography Gear Depreciation Calculator Task

**Difficulty**: 🟡 Medium  
**Skills**: Data cleanup, date functions, conditional formulas, depreciation calculations, business logic  
**Duration**: 240 seconds (4 minutes)  
**Steps**: ~15

## Objective

Help a professional photographer calculate equipment depreciation for tax purposes. The task involves cleaning messy data (inconsistent date formats, missing values), calculating asset age, applying category-based depreciation rules, and identifying equipment worth selling.

## Scenario

You're a professional photographer preparing your year-end tax return. Your gear inventory spreadsheet has accumulated data quality issues over time:
- Purchase dates in various formats ("2021-03-15", "March 2022", "Jan 2020", "01/15/2022")
- Some missing purchase prices (you forgot to log them)
- Need to calculate depreciation using straight-line method for IRS Schedule C

## Task Description

The agent must:

### Part 1: Data Cleanup
1. **Standardize Purchase Dates**: Convert all dates to consistent format (YYYY-MM-DD or DD/MM/YYYY)
   - Handle: "March 2022" → "2022-03-01"
   - Handle: "Jan 2020" → "2020-01-01"
   - Handle: "November 2019" → "2019-11-01"
2. **Fill Missing Prices**: The Godox AD600 Pro is missing its purchase price (~$900 typical)

### Part 2: Calculate Depreciation
Add these calculated columns:

3. **Years Owned** (Column F or later)
   - Formula: Calculate time between Purchase Date and TODAY()
   - Use: `=(TODAY()-C2)/365.25` or `=DATEDIF(C2,TODAY(),"y")+DATEDIF(C2,TODAY(),"yd")/365.25` or `=YEARFRAC(C2,TODAY())`
   - Result: Decimal years (e.g., 2.7 years)

4. **Useful Life (Years)** (Column G or later)
   - Conditional formula based on Category (Column B):