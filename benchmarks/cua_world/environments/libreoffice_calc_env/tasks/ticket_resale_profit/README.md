# Ticket Resale Profit Tracker Task

**Difficulty**: 🟡 Medium  
**Skills**: Conditional formulas, percentage calculations, data analysis, conditional formatting  
**Duration**: 240 seconds (4 minutes)  
**Steps**: ~15

## Objective

Fix profit calculations in a ticket resale tracking spreadsheet by adding fee columns and correcting formulas to account for platform fees. This task tests conditional logic, percentage calculations, and financial analysis skills.

## Scenario

You've been tracking ticket resale transactions but just realized your profit calculations are wrong! You've been calculating profit as simply `Sale Price - Purchase Price`, but you forgot about all the platform fees eating into your margins. Time to fix this and see your real profit (or losses).

## Task Description

The agent must:
1. Open the existing ticket resale spreadsheet with incorrect profit calculations
2. Understand the fee structure for different platforms
3. Add a "Purchase Fee" column with formula: 10% for StubHub purchases, 0% otherwise
4. Add a "Selling Fee" column with formula: 15% for StubHub sales, 12% for Ticketmaster, 0% for cash/Venmo
5. Add a "Payment Processing Fee" column with formula: 2.9% for platform sales, 0% for cash/Venmo
6. Fix the "True Profit" column to subtract all fees
7. Apply conditional formatting to highlight negative profits in red
8. Save the corrected file

## Fee Structure

### Purchase Fees
- **StubHub**: 10% of purchase price
- **Direct/Friend/Venue**: 0%

### Selling Fees
- **StubHub**: 15% of sale price
- **Ticketmaster**: 12% of sale price
- **Venmo/Cash**: 0%

### Payment Processing
- **Platform sales** (StubHub, Ticketmaster): 2.9% of sale price
- **Cash/Venmo**: 0%

## Expected Results

### Purchase Fee Column (Example)
- Formula: `=IF(D2="StubHub", C2*0.10, 0)`
- Calculates 10% of purchase price if bought via StubHub

### Selling Fee Column (Example)
- Formula: `=IF(F2="StubHub", E2*0.15, IF(F2="Ticketmaster", E2*0.12, 0))`
- Nested IF for different platform rates

### Payment Processing Fee Column (Example)
- Formula: `=IF(OR(F2="StubHub", F2="Ticketmaster"), E2*0.029, 0)`
- 2.9% for platform sales only

### True Profit Column (Example)
- Formula: `=E2-C2-G2-H2-I2`
- Sale price minus purchase price minus all three fee types

## Verification Criteria

1. ✅ **Purchase Fee Formula**: Correct IF statement for StubHub 10% fee
2. ✅ **Selling Fee Formula**: Correct nested IF for platform-specific fees
3. ✅ **Processing Fee Formula**: Correct OR condition with 2.9% rate
4. ✅ **Profit Formula**: Subtracts all fee columns correctly
5. ✅ **Calculation Accuracy**: Spot-checked rows are mathematically correct
6. ✅ **Conditional Formatting**: Negative profits highlighted in red
7. ✅ **Column Structure**: All required columns present

**Pass Threshold**: 75% (5/7 criteria must pass)

## Skills Tested

- IF function with conditional logic
- Nested IF statements
- OR function for multiple conditions
- Percentage calculations
- Cell references in formulas
- Conditional formatting rules
- Financial data analysis
- Formula debugging

## Sample Data Structure

| Ticket Description | Purchase Price | Purchase Platform | Sale Price | Sale Platform | Old Profit (WRONG) |
|--------------------|----------------|-------------------|------------|---------------|-------------------|
| Taylor Swift Floor | $450 | StubHub | $620 | StubHub | $170 |
| NBA Finals Upper | $180 | Direct | $240 | Venmo | $60 |

After fixes, you'll add:
- Purchase Fee column
- Selling Fee column  
- Payment Processing Fee column
- True Profit column (corrected)

## Tips

- Read the fee structure carefully before starting
- Use IF statements for conditional calculations
- Nest IF statements when you have multiple conditions
- Use OR() for checking multiple platform values
- Apply formulas to first data row, then copy down
- Conditional formatting: Select column → Format → Conditional Formatting
- Some transactions will show negative profit (you lost money!)