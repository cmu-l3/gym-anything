# Student Loan Payment Strategy Task

**Difficulty**: 🟡 Medium  
**Skills**: Financial formulas, data analysis, sorting, decision-making  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Build a loan payment tracking spreadsheet that calculates how extra payments affect payoff timeline and total interest paid. Analyze multiple student loans with different interest rates to determine the optimal payment strategy (avalanche method - highest interest first).

## Scenario Context

You graduated two years ago and have been making minimum payments on four student loans. You just got a raise and want to put an extra $200/month toward your loans. You need to determine which loan to prioritize with extra payments to minimize total interest paid.

## Task Description

The agent must:
1. Review the pre-populated loan data (4 loans with balances, interest rates, minimum payments)
2. Calculate monthly interest rate for each loan (Annual % / 12)
3. Calculate monthly interest charge in dollars (Balance × Monthly Rate)
4. Calculate principal portion of minimum payment (Payment - Interest)
5. Calculate approximate months to payoff (or similar analysis)
6. Sort loans by interest rate (highest to lowest) to identify priority
7. Identify which loan should receive extra payments
8. Apply appropriate formatting (currency, percentages)

## Starting Data

| Loan Name | Current Balance | Interest Rate (Annual %) | Minimum Payment |
|-----------|----------------|-------------------------|-----------------|
| Federal Direct | $12,500 | 4.5% | $150 |
| Private Bank A | $8,200 | 7.2% | $120 |
| Perkins Loan | $3,800 | 5.0% | $75 |
| Private Bank B | $6,100 | 6.8% | $95 |

## Expected Results

- **Monthly Interest Rate** column: Annual rate divided by 12 (e.g., 7.2% → 0.6%)
- **Monthly Interest $** column: Dollar amount of interest per month
- **Principal from Payment** column: How much of minimum payment reduces balance
- **Months to Payoff** column (optional): Estimated payoff timeline
- **Sorted by interest rate**: Highest rate first (Private Bank A at 7.2% should be top)
- **Priority identification**: Some indication that highest interest loan is the target

## Verification Criteria

1. ✅ **Monthly Interest Calculation Present**: Column with monthly interest rate or dollar amount
2. ✅ **Interest Formulas Correct**: Mathematical accuracy within ±5% tolerance
3. ✅ **Payment Analysis Present**: Principal allocation or payoff timeline calculated
4. ✅ **Loans Sorted by Rate**: Data ordered by interest rate (descending)
5. ✅ **Priority Identified**: Highest interest loan marked as target
6. ✅ **Formatting Applied**: Currency and percentage formats used
7. ✅ **Data Integrity**: All original loan data preserved

**Pass Threshold**: 70% (requires 5/7 criteria)

## Skills Tested

- Financial calculations (interest, payment allocation)
- Formula creation with cell references
- Data sorting and organization
- Multi-criteria analysis
- Decision-making based on data
- Professional spreadsheet formatting

## Tips

- Convert annual interest rate to monthly by dividing by 12
- Monthly interest charge = Current Balance × Monthly Interest Rate
- Principal portion = Minimum Payment - Interest Charge
- Higher interest rates cost more over time - prioritize them first
- Use currency format for dollar amounts ($)
- Use percentage format for rates (%)