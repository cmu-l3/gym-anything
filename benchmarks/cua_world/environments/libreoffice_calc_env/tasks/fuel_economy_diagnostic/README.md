# Fuel Economy Diagnostic Analyzer Task

**Difficulty**: 🟡 Medium  
**Skills**: Data cleaning, formula creation, conditional formatting, pattern analysis  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Help a frustrated car owner diagnose why their fuel economy suddenly dropped by analyzing fill-up logs. Clean messy real-world data, calculate actual MPG for each tank, and use conditional formatting to identify problematic fill-ups. This represents a common diagnostic spreadsheet workflow for finding the ROOT CAUSE of an unexpected change.

## Scenario

A car owner has been manually logging their fill-ups for 2 months and noticed their MPG has dropped from the expected 32 MPG baseline. The data is messy (typical of manual logging) with text mixed in numbers, inconsistent category formatting, and even a duplicate entry. They need help cleaning and analyzing the data to find patterns.

## Task Description

The agent must:
1. Open the messy fuel log CSV file (provided)
2. Clean the "Miles Driven" column (remove text like "mi", "miles")
3. Clean the "Gallons Filled" column (remove text like "gal", "gallons")
4. Standardize the "Weather" column (Hot, Warm, Cold, Mild - consistent capitalization)
5. Standardize the "AC Usage" column (Yes or No - consistent)
6. Identify and remove the duplicate entry (same date, miles, gallons)
7. Create an "MPG Calculated" column with formulas (=Miles/Gallons)
8. Create a "Performance" column with IF logic (Good ≥32, Fair 29-31, Poor <29)
9. Apply conditional formatting to highlight poor MPG values (< 30 or color scale)
10. Save the cleaned and analyzed file

## Expected Results

**Data Cleaning:**
- Miles and Gallons columns contain only numeric values
- Weather: "Hot", "Warm", "Cold", "Mild" (standardized)
- AC Usage: "Yes" or "No" (standardized)
- Duplicate entry removed (17 rows remain from original ~18)

**Calculations:**
- MPG Calculated column with division formulas (not hardcoded values)
- MPG values in reasonable range (18-45 MPG)
- Formulas correctly calculate: MPG = Miles Driven / Gallons Filled

**Analysis:**
- Performance categorization using IF formulas
- Conditional formatting highlights poor performers
- No formula errors (#DIV/0!, #VALUE!, #REF!)

## Verification Criteria

1. ✅ **Clean Numeric Data**: Miles and Gallons columns contain only numbers
2. ✅ **Standardized Categories**: Weather and AC columns have consistent formatting
3. ✅ **Duplicate Removed**: Row count reduced by 1 (15-17 rows remain)
4. ✅ **MPG Formulas Present**: MPG column contains division formulas
5. ✅ **Formulas Calculate Correctly**: Spot-check of 5 rows shows correct MPG
6. ✅ **Conditional Formatting Applied**: Visual highlighting for poor MPG values
7. ✅ **Performance Categories**: IF-based categorization column created
8. ✅ **No Formula Errors**: No #DIV/0!, #VALUE!, or #REF! errors
9. ✅ **Data Integrity**: Valid entries preserved, MPG in reasonable range

**Pass Threshold**: 75% (at least 6 out of 9 criteria)

## Skills Tested

### Data Cleaning
- Text removal from numeric fields (Find & Replace or manual editing)
- Category standardization (consistent formatting)
- Duplicate detection and removal

### Formula Application
- Division formulas with cell references
- IF statements for conditional logic
- Formula propagation across rows

### Data Analysis
- Conditional formatting rules
- Pattern recognition across multiple variables
- Quality validation (spotting unreasonable values)

### Calc Knowledge
- Text-to-number conversion
- Formula syntax and cell references
- Conditional formatting dialog
- Data sorting and filtering

## Sample Data Structure

### Before Cleaning: