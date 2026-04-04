# Mileage Tax Deduction Task

**Difficulty**: 🟡 Medium  
**Skills**: Formula creation, data cleanup, financial calculations  
**Duration**: 180 seconds  
**Steps**: ~20

## Objective

Complete a business mileage log for tax deduction purposes by calculating missing distances, categorizing business miles, applying IRS standard mileage rates, and computing total deductions. This task simulates real-world tax preparation where freelancers and contractors must maintain accurate mileage records.

## Task Description

The agent must:
1. Open a CSV file containing incomplete mileage records
2. Calculate missing distances using odometer readings (End Odo - Start Odo)
3. Identify and populate business miles based on trip purpose
4. Apply the IRS standard mileage rate ($0.655 per mile for 2023)
5. Calculate deduction amounts (Business Miles × Rate)
6. Create SUM formulas for total business miles and total deductions
7. Format deduction column as currency
8. Save the completed spreadsheet

## Data Structure

The CSV contains these columns:
- **Date**: Trip date
- **Start Odo**: Starting odometer reading
- **End Odo**: Ending odometer reading
- **Distance**: Trip distance (some blank, need calculation)
- **Purpose**: Trip description (indicates business vs. personal)
- **Business Miles**: Miles eligible for deduction (some blank)
- **Rate**: IRS standard mileage rate
- **Deduction**: Calculated deduction amount (all blank)

## Business Trip Indicators

Trips with purposes containing these keywords are business trips:
- "Client", "Meeting", "Site", "Conference", "Training", "Office", "Workshop"

Personal trips (e.g., "grocery", "doctor", "family", "shopping") have 0 business miles.

## Expected Results

- **Distance column**: Formulas like `=C2-B2` for rows with odometer readings
- **Business Miles**: Equal to Distance for business trips, 0 for personal trips
- **Rate column**: Consistent rate of 0.655 for all rows
- **Deduction column**: Formulas like `=F2*G2` with currency formatting
- **Totals row**: SUM formulas for Business Miles and Deductions

## Verification Criteria

1. ✅ **Distance Formulas Present**: ≥80% of applicable rows have subtraction formulas
2. ✅ **Business Miles Correct**: 100% accurate categorization based on purpose
3. ✅ **Deduction Formulas Present**: ≥80% of applicable rows have multiplication formulas
4. ✅ **Deduction Calculations Accurate**: Within $0.50 tolerance per row
5. ✅ **Total Business Miles Correct**: SUM formula present and accurate (±1 mile)
6. ✅ **Total Deduction Correct**: SUM formula present and accurate (±$1.00)
7. ✅ **Proper Formatting**: Currency values show $ and decimals
8. ✅ **Data Completeness**: No inappropriate blank cells

**Pass Threshold**: 70% (6/8 criteria must pass)

## Skills Tested

- Formula creation and copying
- Cell referencing (relative and absolute)
- Business logic application
- Data categorization
- Currency formatting
- SUM function usage
- Data cleanup and completion

## Real-World Context

This task reflects a common March/April scenario where self-employed individuals prepare tax documentation. Proper mileage tracking can result in thousands of dollars in legitimate business deductions, but requires accurate, detailed records that would survive an IRS audit.

## Tips

- Use `=C2-B2` for distance calculation (End - Start odometer)
- Copy formulas down efficiently using Ctrl+D or fill-down
- For business trips, Business Miles = Distance
- Deduction formula: `=F2*G2` (Business Miles × Rate)
- Use `=SUM(F2:F11)` for total business miles
- Apply currency format: Format → Cells → Currency