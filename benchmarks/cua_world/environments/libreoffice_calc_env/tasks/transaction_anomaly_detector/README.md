# Transaction Anomaly Detector Task

**Difficulty**: 🟡 Medium  
**Skills**: Data validation, statistical analysis, conditional logic, pattern detection  
**Duration**: 300 seconds  
**Steps**: ~15

## Objective

Identify and flag suspicious transactions in imported bank data using logical rules, statistical analysis, and pattern recognition. This simulates a real-world data quality crisis where imported data contains duplicates, corrupted amounts, impossible dates, and calculation errors.

## Task Description

Sarah imported 3 months of bank transactions from a CSV export, but the bank's export feature has known bugs. She needs to systematically identify ALL suspicious transactions before her tax deadline in 2 days. She can't afford to check 287 transactions manually.

The agent must:
1. Analyze the transaction data for anomalies
2. Create validation formulas to detect:
   - Duplicate transactions (same date, merchant, amount)
   - Invalid dates (future dates or dates outside expected range)
   - Statistical outliers (amounts 3+ standard deviations from category mean)
   - Impossible amounts (negative values, unrealistically large amounts)
   - Balance calculation errors (running balance mismatches)
3. Flag suspicious transactions with appropriate severity
4. Apply visual highlighting for easy review
5. Provide summary of findings

## Data Structure

Columns: Date, Merchant, Category, Amount, Type (Debit/Credit), Balance

**Known Planted Anomalies (15 total):**
- 3 duplicate transaction pairs
- 2 future dates
- 1 ancient date (from 2015)
- 4 statistical outliers
- 2 impossible amounts
- 3 balance calculation errors

## Success Criteria

1. ✅ **Validation structure created**: New column(s) with formulas added
2. ✅ **High recall**: ≥12 of 15 known anomalies flagged (80% recall)
3. ✅ **Acceptable precision**: ≥60% of flags are true anomalies
4. ✅ **Critical anomalies caught**: All duplicates, future dates, and impossible amounts detected
5. ✅ **Formula sophistication**: Uses appropriate Calc functions (COUNTIFS, IF, AVERAGE, STDEV, etc.)
6. ✅ **Visual indication**: Conditional formatting or clear marking applied

**Pass Threshold**: 70% (requires detecting at least 10 of 15 anomalies with reasonable precision)

## Skills Tested

- Multi-step formula creation (nested IF statements)
- Duplicate detection using COUNTIFS
- Date validation and arithmetic
- Statistical analysis (mean, standard deviation, outlier detection)
- Business logic rules implementation
- Conditional formatting
- Quality assurance thinking

## Expected Approach

**Recommended columns to add:**
- `Anomaly_Flags`: Text description of issues found
- `Severity`: High/Medium/Low classification
- Helper columns for intermediate calculations

**Validation formulas should check:**
1. **Duplicates**: `=IF(COUNTIFS($B:$B,B2,$D:$D,D2,$E:$E,E2)>1,"DUPLICATE","")`
2. **Date validation**: Compare dates to TODAY() and reasonable ranges
3. **Outliers**: Calculate category mean/stdev, flag values >3σ away
4. **Business rules**: Negative amounts, category/amount mismatches
5. **Balance validation**: Calculate running balance, compare to provided balance

## Tips

- Use absolute references ($A:$A) for column ranges in COUNTIFS
- AVERAGEIF and STDEVIF help calculate statistics by category
- Nested IF statements can combine multiple checks
- Conditional formatting makes anomalies visually obvious
- Create a summary section showing counts by anomaly type