# Babysitting Co-op Time Bank Reconciliation Task

**Difficulty**: 🟡 Medium  
**Skills**: SUMIF formulas, data cleaning, conditional formatting, balance calculations  
**Duration**: 180 seconds  
**Steps**: ~12

## Objective

Reconcile a messy babysitting co-op time-bank ledger where neighborhood families earn and spend "sitting hours" by watching each other's children. Create a summary table with accurate balances and highlight problem accounts.

## Task Description

A neighborhood babysitting co-op tracks reciprocal childcare using a time-banking system. Families earn hours by babysitting for others and spend hours when others babysit for them. The transaction log has become messy with inconsistent family name entries.

Your task:
1. Review the transaction log with columns: Date, Provider Family, Client Family, Hours
2. Create a summary table showing each family's balance
3. Use SUMIF formulas to calculate hours earned (as provider) and spent (as client)
4. Calculate net balance (earned - spent)
5. Apply conditional formatting to flag families owing more than 5 hours (balance < -5)

## Expected Results

### Summary Table Structure
Create a table with these columns:
- **Family Name**: Each unique family in the co-op
- **Hours Earned**: Total hours babysitting for others (use SUMIF on Provider Family column)
- **Hours Spent**: Total hours receiving babysitting (use SUMIF on Client Family column)
- **Net Balance**: Earned minus Spent (positive = has credit, negative = owes time)

### Conditional Formatting
- Apply to Net Balance column
- Rule: Cells with value less than -5 should be highlighted (red/orange background)
- This flags families who owe significant time to the co-op

## Verification Criteria

1. ✅ **Summary Table Exists**: Four-column table with appropriate headers found
2. ✅ **SUMIF Formulas Present**: Hours Earned and Hours Spent use SUMIF aggregation
3. ✅ **Balance Calculated**: Net Balance uses formula (not hardcoded values)
4. ✅ **Calculations Accurate**: Balance values are mathematically correct (±0.5 tolerance)
5. ✅ **Conditional Formatting Applied**: Formatting rule exists for values < -5
6. ✅ **At Least One Family Flagged**: At least one family has balance < -5 with highlighting
7. ✅ **Realistic Distribution**: Mix of positive/negative balances (not all zeros)

**Pass Threshold**: 70% (5 out of 7 criteria must pass)

## Skills Tested

- **SUMIF Function**: Aggregate hours by matching family names
- **Data Standardization**: Handle inconsistent name entries
- **Formula Creation**: Build cell references and calculations
- **Conditional Formatting**: Create rules based on numeric thresholds
- **Problem Solving**: Understand reciprocal exchange systems

## Real-World Context

This task reflects authentic challenges in:
- Community time-banking systems
- Volunteer coordination
- Mutual aid network tracking
- Ensuring fairness in reciprocal exchanges

## Tips

- The transaction log has intentional name inconsistencies (e.g., "Johnson" vs "Johnsons")
- You can standardize names or use formulas that handle variations
- SUMIF syntax: `=SUMIF(range_to_check, criteria, sum_range)`
- Example: `=SUMIF($B$2:$B$30, F2, $D$2:$D$30)` for hours earned
- Negative balances mean the family owes time to the co-op
- Positive balances mean the family has credit (others owe them)

## Sample SUMIF Formulas
