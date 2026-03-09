# Blood Donation Eligibility Checker Task

**Difficulty**: 🟡 Medium  
**Skills**: Date functions, conditional logic, data cleaning, formula construction  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Work with a blood donation history log containing messy date data to determine eligibility for next donation. Calculate days since last donation, apply donation-type-specific waiting period rules, and identify when the person can donate again.

## Task Description

The agent must:
1. Open a CSV file with blood donation history (mixed date formats)
2. Standardize or handle the Date column
3. Add column "Days Since Donation" using DAYS() and TODAY() functions
4. Add column "Waiting Period (Days)" with conditional logic based on donation type
5. Add column "Eligible?" comparing days since vs. waiting period
6. Add column "Next Eligible Date" calculating date + waiting period
7. Format date columns appropriately
8. Save the file as ODS

## Blood Donation Waiting Periods

- **Whole Blood**: 56 days (8 weeks)
- **Platelets**: 7 days (1 week)
- **Plasma**: 28 days (4 weeks)
- **Double Red Cells**: 112 days (16 weeks)

## Expected Results

New columns added with formulas:
- **Days Since Donation**: `=DAYS(TODAY(), [Date Cell])`
- **Waiting Period (Days)**: `=IF([Type]="Whole Blood", 56, IF([Type]="Platelets", 7, IF([Type]="Plasma", 28, IF([Type]="Double Red Cells", 112, "Unknown"))))`
- **Eligible?**: `=IF([Days Since] >= [Waiting Period], "YES", "NO")`
- **Next Eligible Date**: `=[Date Cell] + [Waiting Period]`

## Verification Criteria

1. ✅ **Required Columns Present**: Days Since, Waiting Period, Eligible?, Next Eligible Date (at least 3/4)
2. ✅ **Formulas Use Correct Functions**: DAYS(), TODAY(), IF() detected
3. ✅ **Calculation Accuracy**: Sample calculations within ±1 day tolerance
4. ✅ **Eligibility Logic Correct**: YES/NO determination is accurate
5. ✅ **No Formula Errors**: Zero #VALUE! or #REF! errors
6. ✅ **Date Formatting Applied**: Next Eligible Date shows as readable date

**Pass Threshold**: 70% (4/6 criteria must pass)

## Skills Tested

- Date parsing and standardization
- DAYS() and TODAY() functions
- Nested IF() conditional logic
- Date arithmetic
- Formula construction with absolute/relative references
- Column formatting (dates vs. numbers)
- Real-world data cleaning

## Starting Data (Messy CSV)
