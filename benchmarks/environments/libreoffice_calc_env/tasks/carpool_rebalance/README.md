# School Carpool Fair Share Calculator Task

**Difficulty**: 🟡 Medium  
**Skills**: Formula debugging, data auditing, cost reconciliation, COUNTIF, SUMIF, cell references  
**Duration**: 240 seconds (4 minutes)  
**Steps**: ~50

## Objective

Repair and rebalance a school carpool coordination spreadsheet that has fallen out of sync. Fix broken formulas, update outdated mileage data, and recalculate fair cost distribution among participating families.

## Scenario

A parent managing a 5-family carpool discovers several problems:
- **Rotation imbalance**: Garcia family has driven 7 times while Kim family only drove 3 times
- **Outdated data**: Martinez family moved to a new address (mileage needs updating from 4.2 to 5.8 miles)
- **Broken formulas**: Gas cost calculations show #REF errors or incorrect values due to copy-paste mistakes

Your task is to diagnose and fix these issues to restore fairness.

## Task Description

The agent must:
1. Open the carpool spreadsheet with three sheets: Drive Log, Family Info, Cost Summary
2. Audit drive rotation counts per family
3. Update Martinez family mileage from 4.2 to 5.8 miles
4. Fix broken formulas in Cost Summary sheet
5. Recalculate gas costs based on actual miles driven
6. Determine fair share amount (total cost ÷ 5 families)
7. Calculate balance owed/credited per family
8. Verify reconciliation (sum of balances = $0)
9. Save the corrected file

## Spreadsheet Structure

### Sheet 1: Drive Log
Records of carpooling instances with driver, date, passengers, miles

### Sheet 2: Family Info
- Family names
- Current addresses
- Miles to school (one-way)
- **Problem**: Martinez shows 4.2 miles (outdated)

### Sheet 3: Cost Summary
- Drive count per family (uses COUNTIF)
- Total miles driven (drive count × mileage × 2 for round trip)
- Gas cost calculation
- Fair share amount
- Balance owed/credited
- **Problem**: Formulas have incorrect cell references

## Expected Results

After corrections:
- Martinez family mileage updated to 5.8
- All formulas functional (no #REF errors)
- Cost calculations accurate
- Balance reconciliation: sum of all balances = $0.00 (±$0.50)
- Garcia family shows positive balance (owed money)
- Kim family shows negative balance (owes money)

## Verification Criteria

1. ✅ **Mileage Updated**: Martinez family shows 5.8 miles (was 4.2)
2. ✅ **Formulas Fixed**: No #REF errors; formulas reference correct cells
3. ✅ **Cost Formulas Correct**: Uses proper mileage lookup and multiplication
4. ✅ **Balance Reconciled**: Sum of all balances equals $0.00 (±$0.50)
5. ✅ **Fair Share Calculated**: Correctly computed as total_cost / 5
6. ✅ **Math Validated**: Spot-check calculations match expected values

**Pass Threshold**: 80% (5/6 criteria must pass)

## Skills Tested

- **Formula auditing**: Inspect and identify broken cell references
- **COUNTIF function**: Count drive frequency per family
- **VLOOKUP/INDEX-MATCH**: Look up mileage from reference table
- **Cell reference repair**: Fix absolute vs. relative references
- **Cost reconciliation**: Ensure zero-sum financial balance
- **Multi-sheet coordination**: Update data in one sheet that affects others
- **Error diagnosis**: Identify root cause of formula errors

## Setup

The setup script:
- Creates an ODS file with three sheets and realistic carpool data
- Introduces intentional errors (broken formulas, outdated mileage)
- Launches LibreOffice Calc with the file
- Displays instructions in cell A1

## Export

The export script:
- Saves the file as `/home/ga/Documents/carpool_rebalanced.ods`
- Closes LibreOffice Calc

## Verification

Verifier performs comprehensive checks:
1. Parses ODS file and extracts all three sheets
2. Verifies Martinez mileage updated to 5.8
3. Inspects formulas for correctness and valid references
4. Validates cost calculations mathematically
5. Confirms balance reconciliation (zero-sum check)
6. Provides detailed feedback on each criterion

## Tips

- Read the instruction comment in cell A1 of Cost Summary sheet
- Check Family Info sheet for current mileage data
- Use COUNTIF to count drive frequency: `=COUNTIF('Drive Log'.B:B, A2)`
- Use VLOOKUP for mileage lookup: `=VLOOKUP(A2, 'Family Info'.A:C, 3, FALSE)`
- Total miles formula: `drive_count × mileage × 2` (round trip)
- Gas cost formula: `total_miles × (gas_price / mpg)`
- Balance formula: `actual_cost - fair_share`
- Verify reconciliation: `SUM(balances)` should equal 0

## Real-World Context

This task simulates a common spreadsheet maintenance problem: living documents that degrade over time due to copy-paste errors, outdated data, and formula reference breaks. The carpool scenario adds social stakes—fairness matters deeply when coordinating with neighbors and friends.