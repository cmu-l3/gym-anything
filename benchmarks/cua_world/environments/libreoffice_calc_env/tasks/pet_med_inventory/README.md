# Pet Medication Inventory Manager Task (`pet_med_inventory@1`)

**Difficulty**: 🟡 Medium  
**Skills**: Data cleaning, date calculations, conditional formulas, arithmetic  
**Duration**: 240 seconds (4 minutes)  
**Steps**: ~15

## Objective

Clean messy veterinary clinic export data, calculate remaining medication supplies based on dosage schedules and time elapsed, and create an actionable reorder list for multiple pets. This task simulates real-world healthcare management where exported data requires cleanup before useful analysis.

## Task Description

You have exported medication records from your vet clinic's system, but the data is messy with inconsistent date formats and mixed units. You need to:

1. **Clean the data**: Standardize date formats, handle missing values
2. **Calculate consumption**: Determine how many pills have been used since last refill
3. **Calculate inventory**: Determine remaining pills for each medication
4. **Flag urgent refills**: Identify medications with less than 1 week supply
5. **Calculate costs**: Sum up the total cost to reorder all flagged medications

## Starting State

- LibreOffice Calc opens with `pet_medications.ods` containing:
  - Columns: Pet Name, Medication, Start Date, Last Refill, Pills per Bottle, Daily Dosage, Cost per Bottle
  - 6 rows of data for 3 pets (Luna, Max, Bella)
  - Intentional data quality issues:
    - Mixed date formats (MM/DD/YYYY, DD-MMM-YY, YYYY-MM-DD)
    - Missing "Last Refill" dates (shown as blank or "N/A")
    - Inconsistent formatting

## Required Actions

### 1. Data Cleaning (5 minutes)
- **Standardize dates**: Convert all dates in "Last Refill" column to consistent format
- **Handle missing data**: For missing "Last Refill", use "Start Date" as fallback
- **Remove text artifacts**: Clean any extra spaces or notes

### 2. Create Calculated Columns
Add these new columns with formulas:

- **Column I - Days Since Refill**: `=TODAY() - [Last Refill Date]`
- **Column J - Pills Used**: `=[Daily Dosage] * [Days Since Refill]`
- **Column K - Pills Remaining**: `=[Pills per Bottle] - [Pills Used]`
- **Column L - Reorder Needed?**: `=IF([Pills Remaining] < [Daily Dosage]*7, "YES", "NO")`
- **Column M - Days Until Empty**: `=[Pills Remaining] / [Daily Dosage]`
- **Column N - Reorder Cost**: `=IF([Reorder Needed?]="YES", [Cost per Bottle], 0)`

### 3. Total Cost Summary
- At bottom of Reorder Cost column: `=SUM(N2:N7)` (or appropriate range)

## Success Criteria

1. ✅ **Dates Standardized**: All dates in consistent format (no mixed formats)
2. ✅ **Formulas Present**: At least 5 calculated columns contain formulas (not hardcoded values)
3. ✅ **Reorder Logic Correct**: Medications with <7 days supply flagged "YES"
4. ✅ **Calculations Accurate**: Spot-checked rows match expected results
5. ✅ **Total Cost Present**: Valid SUM formula for total reorder costs
6. ✅ **Data Preserved**: All 6 original medication rows remain

**Pass Threshold**: 70% (4 out of 6 criteria)

## Example Calculation

For Luna's Thyroid Pills (assuming today is April 30, 2024):
- Last Refill: 2024-04-03 → **27 days ago**
- Daily Dosage: 2 pills → Pills Used: **2 × 27 = 54**
- Pills per Bottle: 60 → Pills Remaining: **60 - 54 = 6**
- Reorder Needed?: 6 < (2 × 7) → **YES**
- Days Until Empty: 6 / 2 → **3 days**
- Reorder Cost: **$28.50**

## Skills Tested

- Data cleaning and standardization
- Date arithmetic with TODAY() function
- Multi-step formula chains
- IF conditional logic
- Cell references (relative and absolute)
- SUM aggregation
- Logical problem solving
- Real-world data quality handling

## Tips

- Start by standardizing all dates to YYYY-MM-DD format for consistency
- Use Find & Replace (Ctrl+H) to help clean inconsistent formats
- TODAY() function returns the current date automatically
- When Pills Remaining is negative, it means medication is overdue for refill
- Build formulas step by step: Days Since → Pills Used → Pills Remaining → Logic
- Use cell references (like J2) not hardcoded numbers in formulas
- Test your formulas on the first data row before copying down

## Common Pitfalls

- **Hardcoding values**: Entering "54" instead of "=D2*I2" defeats the purpose
- **Circular references**: Referring to the cell you're calculating in
- **Wrong date format**: Dates stored as text won't calculate correctly
- **Absolute vs relative**: Know when to use $A$1 vs A1
- **Off-by-one errors**: Make sure your SUM range includes all data rows

## Real-World Context

This task represents a genuine frustration pet owners face: veterinary clinic software exports are often messy and don't include the analysis needed to manage multiple pets' medications. Missing a refill for thyroid, heart, or seizure medications can have serious health consequences. This spreadsheet helps ensure critical medications never run out.