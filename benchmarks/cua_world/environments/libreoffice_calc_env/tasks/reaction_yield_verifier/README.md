# Chemical Reaction Yield Verification Task

**Difficulty**: 🟡 Medium  
**Skills**: Formula creation, error detection, scientific calculations, conditional formatting  
**Duration**: 180 seconds  
**Steps**: ~50

## Objective

Replicate and verify calculations from a published chemistry experiment. A spreadsheet contains raw lab data and reported yields from a journal article that may contain calculation errors. The agent must apply correct chemical yield formulas, compare results against published values, and identify any discrepancies.

## Task Description

The agent must:
1. Open a spreadsheet containing reaction data with columns:
   - A: Reaction ID (RXN-001, RXN-002, etc.)
   - B: Theoretical Yield (grams)
   - C: Actual Yield (grams)
   - D: Reported % Yield (from published paper)
   - E: Empty (for calculated yield)
   - F: Empty (for discrepancy)

2. In column E, create formulas to calculate % yield: `=(C/B)*100`
3. Copy the formula to all data rows
4. In column F, create formulas to calculate discrepancy: `=E-D`
5. Copy the formula to all data rows
6. (Optional) Apply conditional formatting to highlight discrepancies >0.5

## Expected Results

- **Column E** contains formulas calculating (Actual/Theoretical) × 100
- **Column F** contains formulas calculating Calculated - Reported
- **Formulas** are applied to all data rows (not hardcoded values)
- **Discrepancies** correctly identify 2-3 reactions with calculation errors

## Verification Criteria

1. ✅ **Formulas Present**: Column E contains valid yield formulas (not just values)
2. ✅ **Calculations Correct**: Yields match expected mathematical results (±0.1% tolerance)
3. ✅ **Discrepancies Identified**: Column F correctly computes difference between calculated and reported
4. ✅ **Error Detection**: At least 2 known erroneous reported values are flagged with discrepancies >0.5 pp
5. ✅ **Complete Coverage**: All data rows have calculations (no gaps)

**Pass Threshold**: 80% (4/5 criteria must pass)

## Skills Tested

- Formula syntax and cell references
- Copying formulas with relative references
- Mathematical calculations in scientific context
- Error detection and verification
- Data validation
- (Optional) Conditional formatting

## Formula Reference

**Chemical Yield Formula:**