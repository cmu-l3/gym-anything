# Babysitting Co-op Credit Reconciliation Task

**Difficulty**: 🟡 Medium  
**Skills**: Data cleaning, formula logic, conditional formatting, time calculations  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Clean up messy babysitting co-op transaction records where families exchange childcare hours. Standardize inconsistent time formats, calculate credit balances for each family, and flag accounts with significant imbalances before the monthly co-op meeting.

## Task Description

The agent must:
1. Open a babysitting co-op transaction log with messy time entries
2. Standardize all time entries to decimal hours format
   - Convert "2:30" → 2.5 hours
   - Convert "evening" → 3 hours
   - Convert "afternoon" → 2 hours  
   - Convert "date night" → 4 hours
3. Create a summary table with family credit balances
4. Calculate credits given (hours babysat for others) using SUMIF
5. Calculate credits received (hours others babysat for them) using SUMIF
6. Calculate balance (credits given - credits received)
7. Flag families with |balance| > 5 hours
8. Apply conditional formatting (red for owing, yellow for owed, green for balanced)

## Starting State

- Transaction log with columns: Date | Babysitter_Family | Child_Family | Hours | Notes
- 8 families: Johnson, Patel, Kim, Rodriguez, Chen, Williams, Thompson, Davis
- ~20-25 transactions with inconsistent time formats

## Expected Results

### Data Standardization
- All hours in decimal format (2.5, 3.0, 4.0, etc.)
- No text time descriptions remaining

### Summary Table
| Family Name | Credits Given | Credits Received | Balance | Status |
|-------------|--------------|------------------|---------|---------|
| Johnson     | =SUMIF(...)  | =SUMIF(...)      | =B2-C2  | Formula |
| Patel       | =SUMIF(...)  | =SUMIF(...)      | =B3-C3  | Formula |
| ...         | ...          | ...              | ...     | ...     |

### Status Values
- "Owes Hours" (balance < -5) - Red formatting
- "Owed Hours" (balance > 5) - Yellow formatting
- "Balanced" (-5 ≤ balance ≤ 5) - Green formatting

### System Balance
- Total credits given = Total credits received (zero-sum system)

## Verification Criteria

1. ✅ **Time Data Standardized**: All hours converted to decimal format
2. ✅ **Formulas Present**: Credits calculated with SUMIF, balances with subtraction
3. ✅ **Calculations Accurate**: Spot-check calculations match expected values
4. ✅ **Imbalances Flagged**: Families with |balance| > 5 hours have status flags
5. ✅ **System Balances**: Total credits given ≈ total credits received (±1 hour)
6. ✅ **Conditional Formatting**: Visual highlighting based on balance thresholds
7. ✅ **All Families Present**: Summary includes all 8 families

**Pass Threshold**: 70% (5/7 criteria must pass)

## Skills Tested

- Data cleaning and standardization
- Text-to-number conversion
- SUMIF function for conditional aggregation
- Formula creation with cell references
- IF/AND logic for conditional flagging
- Conditional formatting
- Multi-party accounting (reciprocal transactions)

## Real-World Context

This task simulates a common frustration for community babysitting co-op coordinators:
- Multiple families enter data in different formats
- Need to identify imbalances before the monthly meeting
- Social sensitivity: flagging neighbors who aren't reciprocating
- Burnout prevention: identifying families giving too much
- System integrity: ensuring the co-op remains fair and sustainable

## Tips

- Create summary table on same sheet or new sheet
- Use SUMIF to sum hours by family name: `=SUMIF(range, criteria, sum_range)`
- Balance is positive if family is owed hours, negative if family owes hours
- Conditional formatting: Format → Conditional Formatting → Condition
- System should balance to zero (everyone's hours should net out collectively)