# Blood Donor Eligibility Matcher Task

**Difficulty**: 🟡 Medium  
**Skills**: Date arithmetic, conditional logic, multi-criteria filtering  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Process a blood donor database to identify eligible donors for an urgent blood drive. Calculate eligibility dates based on the 56-day whole blood donation interval, determine current eligibility, and match with urgent blood type needs (O+).

## Task Description

The agent must:
1. Open the blood donor database spreadsheet (provided)
2. Create a "Next Eligible Date" column with formula: Last Donation Date + 56 days
3. Create an "Eligible Now?" column with conditional formula checking if today >= next eligible date
4. Create an "Urgent Match (O+)" column identifying O+ donors who are currently eligible
5. Apply formulas to all donor rows
6. Save the file

## Starting Data

A database with ~15-20 donors containing:
- Donor Name
- Blood Type (O+, O-, A+, A-, B+, B-, AB+, AB-)
- Last Donation Date (dates from 30-120 days ago)
- Phone Number
- Some entries may have missing last donation dates

## Expected Results

**New Columns Added:**
- **Next Eligible Date**: `=<Last Donation Cell> + 56`
- **Eligible Now?**: `=IF(<Next Eligible Cell> <= TODAY(), "YES", "NO")`
- **Urgent Match (O+)**: `=IF(AND(<Blood Type> = "O+", <Eligible Now> = "YES"), "URGENT", "")`

## Verification Criteria

1. ✅ **Next Eligible Date Column**: Exists and contains date calculations
2. ✅ **Date Arithmetic Correct**: Sample verification shows correct 56-day addition
3. ✅ **Eligibility Logic Correct**: "Eligible Now?" accurately reflects date comparison
4. ✅ **Urgent Match Logic**: Compound condition (O+ AND Eligible) properly implemented
5. ✅ **Formula Coverage**: At least 80% of data rows have formulas applied
6. ✅ **Minimal Errors**: Fewer than 10% of cells show formula errors
7. ✅ **Urgent Donors Identified**: At least 2 donors flagged as urgent matches

**Pass Threshold**: 70% (5/7 criteria must pass)

## Skills Tested

- Date arithmetic (DATE + days)
- TODAY() function usage
- IF() conditional logic
- AND() compound conditions
- Text/value comparison
- Formula copying and reference management
- Error handling for missing data

## Real-World Context

Blood banks must maintain adequate inventory while respecting donor health regulations. Whole blood donors must wait 56 days between donations. When urgent needs arise (e.g., trauma cases requiring O+ blood), coordinators must quickly identify eligible donors from their database.

## Tips

- Use `=<cell> + 56` for date addition (LibreOffice Calc automatically handles date arithmetic)
- TODAY() returns the current date
- Use `=IF(condition, "YES", "NO")` for eligibility
- Use `=IF(AND(condition1, condition2), "URGENT", "")` for urgent matching
- Handle missing dates with ISBLANK() or IFERROR() if needed
- Copy formulas down with Ctrl+D or drag fill handle