# Medical Bill Reconciliation Task

**Difficulty**: 🟡 Medium  
**Skills**: Data reconciliation, lookup formulas, conditional logic, financial analysis  
**Duration**: 240 seconds  
**Steps**: ~15

## Objective

Reconcile messy medical billing data by identifying duplicate charges, matching bills to insurance EOB (Explanation of Benefits) statements, flagging discrepancies, and calculating the true amount owed versus what's being billed. This simulates a common real-world scenario where patients must verify medical bills against insurance statements to avoid overpayment.

## Task Description

You receive:
- **Bills sheet**: Contains bills from various providers with dates, procedures, and amounts billed
- **EOB sheet**: Insurance company's Explanation of Benefits showing what you actually owe

The agent must:
1. Match bills to corresponding EOB entries (providers/dates may not match exactly)
2. Identify duplicate bills (same procedure billed multiple times)
3. Calculate discrepancies between billed amounts and EOB patient responsibility
4. Flag bills that should be disputed
5. Apply conditional formatting to visually highlight issues
6. Create a summary showing total billed vs. total actually owed

## Starting State

- LibreOffice Calc opens with a workbook containing two sheets: "Bills" and "EOB"
- Bills sheet has 8 rows of medical bills (some duplicates, some overcharges)
- EOB sheet has 5 rows showing what insurance says you owe
- Data is intentionally messy (provider names slightly different, dates off by a day or two)

## Required Actions

### 1. Create Reconciliation Columns
In the Bills sheet, add columns for:
- **Discrepancy**: Billed amount minus EOB patient responsibility
- **Status**: Values like "OK", "DUPLICATE", "DISPUTE", "NOT IN EOB"
- **EOB Match** (optional): Link to corresponding EOB entry

### 2. Match Bills to EOB
- Use VLOOKUP, INDEX-MATCH, or manual inspection
- Handle fuzzy matching (provider names may differ slightly)
- Allow date tolerance (±2 days)

### 3. Identify Duplicates
- Flag bills appearing multiple times for same provider/date/procedure
- Mark with "DUPLICATE" status

### 4. Calculate Discrepancies
- For each bill matched to EOB: `Discrepancy = Billed - EOB Amount`
- Flag discrepancies > $10 as "DISPUTE"

### 5. Apply Conditional Formatting
- Color-code Status column (e.g., green=OK, yellow=DUPLICATE, red=DISPUTE)

### 6. Create Summary
Add summary section with:
- Total Amount Billed
- Total According to EOB
- Total Overage (potential overpayment)
- Count of duplicates and disputes

## Expected Results

**Known Issues in Dataset:**
- 2 duplicate bills (City Hospital ER visit, Dr. Chen ER physician)
- 1 bill not in EOB (Pharmacy - already paid at counter)
- Total potential overpayment: ~$1,275 if duplicates not caught

## Success Criteria

1. ✅ **Reconciliation Columns Added**: "Discrepancy" and "Status" columns exist and are populated
2. ✅ **Lookup Formulas Present**: Uses VLOOKUP, INDEX-MATCH, or similar
3. ✅ **Duplicates Identified**: At least 2 bills marked as "DUPLICATE"
4. ✅ **Disputes Flagged**: At least 2 bills marked as "DISPUTE" with discrepancy > $10
5. ✅ **Conditional Formatting Applied**: Status column has visual color coding
6. ✅ **Summary Calculations Present**: Summary with Total Billed, Total Owed, Total Overage
7. ✅ **Overage Calculated Correctly**: Shows positive overage amount
8. ✅ **No Formula Errors**: No #N/A, #REF!, #VALUE! errors

**Pass Threshold**: 75% (6 out of 8 criteria)

## Skills Tested

- Multi-sheet workbook navigation
- Lookup formulas (VLOOKUP/INDEX-MATCH)
- Conditional logic (IF statements)
- Conditional formatting
- Data reconciliation and matching
- Financial calculations
- Summary statistics (SUM, SUMIF, COUNTIF)
- Critical thinking under ambiguity

## Tips

- Provider names don't match exactly (e.g., "City Hospital" vs "CITY HOSPITAL")
- Use UPPER() or TRIM() functions to normalize text for matching
- Dates may be off by 1-2 days between Bills and EOB
- Small discrepancies (<$10) may be rounding - focus on material errors
- Some bills may not have corresponding EOB entries
- Look for identical amounts on same dates as potential duplicates