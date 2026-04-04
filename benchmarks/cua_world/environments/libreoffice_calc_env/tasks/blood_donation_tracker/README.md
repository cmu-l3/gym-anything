# Blood Donation Eligibility Tracker Task

**Difficulty**: 🟡 Medium  
**Skills**: Date arithmetic, VLOOKUP/INDEX-MATCH, conditional logic, cell references  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Create formulas to calculate eligibility dates for blood donation based on donation history and medical waiting period requirements. This task tests date calculations, lookup functions, and practical application of spreadsheet logic to a real-world tracking scenario.

## Task Description

You maintain a donation history spreadsheet and need to calculate when you'll next be eligible for different donation types. Medical guidelines specify mandatory waiting periods between donations:

- **Whole Blood**: 56 days
- **Platelets**: 7 days  
- **Plasma**: 28 days
- **Double Red Cells**: 112 days

The agent must:
1. Use VLOOKUP or INDEX-MATCH to retrieve waiting periods from the reference table
2. Calculate next eligible date by adding waiting period to donation date
3. Apply formula to all donation records
4. Create summary formula to identify the next available donation opportunity

## Expected Results

- **Next Eligible Date column**: Contains formulas that calculate: Donation Date + Waiting Period
- **Formulas use lookup functions**: VLOOKUP or INDEX-MATCH to get waiting periods
- **Calculations are accurate**: Spot-checked dates match expected values
- **Summary shows next available**: Minimum future eligible date is identified

## Verification Criteria

1. ✅ **Reference Table Present**: Donation types and waiting periods correctly structured
2. ✅ **Lookup Formula Used**: VLOOKUP or INDEX-MATCH retrieves waiting periods
3. ✅ **Date Arithmetic Correct**: Eligibility = donation date + waiting period
4. ✅ **Calculation Accuracy**: At least 3 dates mathematically correct (±1 day tolerance)
5. ✅ **Next Available Identified**: Summary shows soonest future eligible date
6. ✅ **Proper References**: Formula uses absolute references for reference table

**Pass Threshold**: 75% (4/6 criteria must pass)

## Skills Tested

- Date arithmetic functions
- VLOOKUP or INDEX-MATCH lookup functions
- Absolute vs relative cell references
- Formula application across rows
- MIN function with conditional logic
- Working with multi-sheet workbooks

## Setup

The setup script:
- Creates pre-populated spreadsheet with donation history
- Includes reference table with waiting periods
- Launches LibreOffice Calc
- Positions cursor at the "Next Eligible Date" column

## Starting Data

**Donation Log Sheet:**
- Column A: Donation Date (various dates in 2023-2024)
- Column B: Donation Type (Whole Blood, Platelets, Plasma, Double Red Cells)
- Column C: Next Eligible Date (to be calculated)

**Reference Table Sheet:**
- Column A: Donation Type
- Column B: Waiting Period (Days)

## Export

The export script:
- Saves the file as `/home/ga/Documents/blood_donation_tracker.ods`
- Closes LibreOffice Calc

## Verification

Verifier checks:
1. Reference table structure and values
2. Formula structure (contains VLOOKUP/INDEX-MATCH)
3. Mathematical accuracy of calculated dates
4. Use of absolute references
5. Summary calculation correctness