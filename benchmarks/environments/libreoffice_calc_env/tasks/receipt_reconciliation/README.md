# Receipt Reconciliation Task

**Difficulty**: 🟢 Easy-Medium  
**Skills**: CSV import, SUM formulas, arithmetic, data validation  
**Duration**: 120 seconds  
**Steps**: ~15

## Objective

Import a grocery receipt CSV file, calculate the actual total using formulas, compare it with the store's charged amount, and identify the discrepancy. This task simulates the real-world scenario of catching merchant errors and overcharges.

## Task Description

**Scenario**: You just got home from grocery shopping. The receipt shows a total of **$127.43**, but when you mentally add up the items, it seems too high. You suspect the store made an error. Time to verify!

The agent must:
1. Open the provided CSV file `grocery_receipt.csv` in LibreOffice Calc
2. Review the list of items and their prices
3. Use a SUM formula to calculate the actual total of all item prices
4. Enter the store's claimed total ($127.43)
5. Calculate the discrepancy (difference between charged and actual)
6. Identify the overcharge amount (~$7.76)

## Expected Results

- **Calculated Total**: Should be ~$119.67 (using SUM formula)
- **Store Charged**: $127.43
- **Discrepancy**: ~$7.76 (positive means overcharge)

## Receipt Data

The CSV contains approximately 18-20 grocery items with **intentional errors**:
- One item appears twice (double-scan)
- One item has incorrect pricing

## Verification Criteria

1. ✅ **CSV Data Imported**: Receipt data successfully loaded into spreadsheet
2. ✅ **SUM Formula Present**: Valid SUM formula calculating total of all item prices
3. ✅ **Formula Correctness**: SUM formula produces correct result (~$119.67)
4. ✅ **Discrepancy Calculated**: Formula computing difference between charged and actual
5. ✅ **Correct Discrepancy Value**: Calculated discrepancy is ~$7.76 (±$0.10 tolerance)
6. ✅ **Proper Formatting**: Monetary values displayed appropriately

**Pass Threshold**: 70% (requires 4-5/6 criteria met)

## Skills Tested

- CSV file import and handling
- Cell navigation and selection
- SUM function usage with ranges
- Basic arithmetic (subtraction)
- Cell references
- Formula syntax
- Data validation mindset
- Consumer financial literacy

## Setup

The setup script:
- Creates `grocery_receipt.csv` with intentional errors
- Places file in `/home/ga/Documents/`
- Launches LibreOffice Calc
- Displays task instructions

## Export

The export script:
- Saves the spreadsheet as ODS format
- Preserves formulas and calculations
- Closes LibreOffice Calc

## Verification

Verifier checks:
1. CSV data imported with all items
2. SUM formula exists and covers all price cells
3. Formula calculation is mathematically correct
4. Charged amount ($127.43) is present
5. Discrepancy formula exists (subtraction)
6. Discrepancy value matches expected error amount

## Tips

- Open the CSV using File → Open or double-click
- The Item and Price columns should be clearly visible
- Use =SUM(range) to add all prices
- Store's total is provided in the task description ($127.43)
- Discrepancy = Charged - Calculated
- A positive discrepancy means you were overcharged