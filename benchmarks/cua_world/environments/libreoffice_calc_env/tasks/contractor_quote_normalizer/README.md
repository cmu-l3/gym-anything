# Contractor Quote Comparison Task

**Difficulty**: 🟡 Medium  
**Skills**: Data cleaning, formula creation, conditional formatting, analytical thinking  
**Duration**: 240 seconds (4 minutes)  
**Steps**: ~20

## Objective

Normalize and compare three contractor quotes that arrive in wildly different formats. Clean inconsistent data, create standardized comparison tables, identify cost outliers, and determine which contractor offers the best value for required work.

## Task Description

You receive three contractor quotes for roof repair that are formatted completely differently:
- **Quote 1**: Itemized with separate labor/materials
- **Quote 2**: Bundled "complete installation" pricing  
- **Quote 3**: Mixed required and optional work without clear separation

The agent must:
1. Analyze the messy quote data provided in the spreadsheet
2. Create a standardized comparison structure with consistent categories
3. Separate required work from optional add-ons
4. Calculate comparable totals for each contractor
5. Apply conditional formatting to highlight best values and outliers
6. Create a summary section showing the best value contractor

## Starting Data

The spreadsheet contains three contractor quotes with intentionally inconsistent formatting:

**Contractor A - Smith Roofing (Itemized)**
- Labor, Materials (shingles, underlayment, flashing), Disposal fee
- Does NOT include permit fees

**Contractor B - Quick Fix Roofs (Bundled)**  
- "Complete installation" bundle
- Includes everything except optional gutter work
- Doesn't break out components

**Contractor C - Joe's Roofing (Mixed)**
- Lower prices but unclear scope
- Mixes required and optional items
- Suspiciously low total (possible red flag)

## Expected Results

A well-structured comparison with:
- **Standardized categories**: Materials, Labor, Permits/Fees, Optional
- **Accurate formulas**: SUM for subtotals and totals
- **Clear winner identification**: MIN formula or ranking showing lowest-cost contractor
- **Outlier highlighting**: Items >30% above/below average flagged
- **Summary section**: Quick comparison table with totals and rankings

## Verification Criteria

1. ✅ **Data Standardized**: 4+ consistent categories across contractors
2. ✅ **Formulas Correct**: Total calculations accurate (within $1)
3. ✅ **Best Value Identified**: MIN or ranking formula present
4. ✅ **Outliers Flagged**: At least 2 outlier items highlighted
5. ✅ **Summary Exists**: Comparison section with totals/rankings

**Pass Threshold**: 80% (4/5 criteria must pass)

## Skills Tested

- Data cleaning and standardization
- Formula construction (SUM, AVERAGE, MIN, IF)
- Conditional formatting application
- Text functions for cleaning
- Statistical outlier detection
- Decision support table design

## Tips

- Create standard category headers first (Materials, Labor, Permits, Optional)
- Map each contractor's items to your categories
- Use SUM formulas for subtotals, not hardcoded values
- Apply conditional formatting: Home → Conditional Formatting
- Create a "Summary" section at the bottom or side
- Use MIN() to identify lowest cost
- Flag items where one contractor is >30% different from others