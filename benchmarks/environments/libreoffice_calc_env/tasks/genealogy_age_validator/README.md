# Genealogy Record Consistency Checker Task

**Difficulty**: 🟡 Medium  
**Skills**: Formula chaining, conditional logic, data quality assessment, ABS function, IF function  
**Duration**: 180 seconds  
**Steps**: ~20

## Objective

Analyze genealogy research data to identify age inconsistencies between known birth years and recorded ages in historical documents. Calculate implied birth years from census records and flag suspicious discrepancies that require further investigation.

## Task Description

You're helping a genealogy researcher validate historical records. The spreadsheet contains:
- **Column A:** Person Name
- **Column B:** Known Birth Year (from reliable sources like birth certificates)
- **Column C:** Record Date (year of census/document)
- **Column D:** Recorded Age (age claimed in that record)
- **Column E:** Implied Birth Year (EMPTY - you calculate this)
- **Column F:** Flag Inconsistency (EMPTY - you calculate this)

## Your Tasks

1. **Calculate Implied Birth Year (Column E)**
   - Formula: `=C2-D2` (Record Date - Recorded Age)
   - Copy this formula down to all data rows

2. **Flag Inconsistencies (Column F)**
   - Formula: `=IF(ABS(B2-E2)>2,"INVESTIGATE","OK")`
   - This flags records where the discrepancy exceeds 2 years
   - Copy this formula down to all data rows

## Why This Matters

Historical records have errors for many reasons:
- Census takers made transcription mistakes
- People lied about their age
- Handwriting was misread during digitization
- Different calendar systems caused confusion

A discrepancy of 1-2 years is acceptable, but larger gaps indicate problems.

## Example

| Name | Known Birth | Record Date | Recorded Age | Implied Birth | Flag |
|------|-------------|-------------|--------------|---------------|------|
| Sarah | 1850 | 1895 | 40 | 1855 | INVESTIGATE |
| John | 1845 | 1880 | 35 | 1845 | OK |

Sarah should be 45 in 1895 (not 40), so this record needs investigation.

## Expected Results

- **Column E:** All cells contain formulas calculating implied birth years
- **Column F:** All cells contain IF/ABS formulas flagging inconsistencies
- **Some "INVESTIGATE" flags:** Records with discrepancies >2 years
- **Some "OK" flags:** Records with acceptable discrepancies ≤2 years

## Verification Criteria

1. ✅ **Implied Birth Year Formula:** Column E contains correct subtraction formula (C-D)
2. ✅ **Flag Formula Structure:** Column F contains IF(ABS(B-E)>2,...) logic
3. ✅ **Calculation Accuracy:** Sample calculations are mathematically correct
4. ✅ **Complete Application:** Formulas applied to all data rows
5. ✅ **Correct Flagging:** At least one "INVESTIGATE" and one "OK" appear
6. ✅ **No Empty Cells:** All data rows have calculated values

**Pass Threshold**: 70% (requires 4/6 criteria)

## Skills Tested

- Cell formula entry and syntax
- Formula propagation (fill-down)
- Arithmetic operations (subtraction)
- ABS function for absolute differences
- IF function for conditional logic
- Understanding cell references
- Multi-step formula dependencies

## Tips

- Start with cell E2 for the first formula
- After entering formula in E2, copy it down to all rows with data
- Then move to F2 for the flag formula
- The ABS function ensures positive differences regardless of order
- Use Ctrl+C and Ctrl+V to copy formulas efficiently
- Double-check that formulas reference the correct columns