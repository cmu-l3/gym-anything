# Credit Card Rewards Optimizer Task

**Difficulty**: 🟡 Medium  
**Skills**: Percentage calculations, conditional logic, comparative analysis, financial formulas  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Create a decision-making tool that analyzes multiple credit cards with different reward structures and determines which card provides the best cashback for each spending category. This task tests formula creation, percentage calculations, and conditional logic to solve a real-world personal finance optimization problem.

## Scenario

You have three credit cards with different cashback reward structures:
- **Card A**: 3% on groceries, 2% on gas, 1% on everything else
- **Card B**: 2% on dining, 2% on gas, 1.5% on everything else
- **Card C**: 2% flat rate on all purchases

You need to build a spreadsheet that calculates which card gives you the most cashback for each spending category based on your typical monthly spending.

## Task Description

The agent must:
1. Create a structured table with spending categories and card options
2. Input monthly spending amounts for different categories
3. Enter reward percentages for each card-category combination
4. Create formulas to calculate cashback amounts (spending × reward percentage)
5. Use MAX or nested IF functions to identify the optimal card for each category
6. Calculate total optimized rewards
7. Save the file as credit_card_optimizer.ods

## Required Data Structure

### Categories (rows)
- Groceries (example: $600/month)
- Gas (example: $200/month)
- Dining (example: $300/month)
- General Purchases (example: $400/month)

### Card Reward Structures (columns)
- Card A rewards per category
- Card B rewards per category
- Card C rewards per category
- Best Card recommendation

## Expected Results

- **Formulas**: Each card-category cell should contain `=Spending * Percentage` formula
- **Optimization**: MAX or nested IF functions to identify highest cashback
- **Calculations**: Accurate dollar amounts for cashback values
- **Recommendations**: Clear indication of which card to use for each category

## Example Structure

| Category | Spending | Card A (CB) | Card B (CB) | Card C (CB) | Best Card |
|----------|----------|-------------|-------------|-------------|-----------|
| Groceries| $600     | =B2*0.03    | =B2*0.01    | =B2*0.02    | Card A    |
| Gas      | $200     | =B3*0.02    | =B3*0.02    | =B3*0.02    | Any       |
| Dining   | $300     | =B4*0.01    | =B4*0.02    | =B4*0.02    | Card B    |
| General  | $400     | =B5*0.01    | =B5*0.015   | =B5*0.02    | Card C    |

## Verification Criteria

1. ✅ **Structured Data**: Table with 3+ categories and 3+ cards
2. ✅ **Cashback Formulas**: At least 6 cells with multiplication formulas
3. ✅ **Optimization Logic**: MAX or nested IF formulas present
4. ✅ **Calculation Accuracy**: Spot-check calculations within tolerance
5. ✅ **Recommendations**: Clear indication of best card per category
6. ✅ **File Saved**: Properly saved as ODS format

**Pass Threshold**: 67% (4 out of 6 criteria must pass)

## Skills Tested

- Table structure design
- Percentage-based calculations
- Formula creation with cell references
- Conditional logic (IF statements)
- MAX function for optimization
- Financial decision modeling
- Currency formatting (optional)

## Tips

- Start by creating clear row and column headers
- Use percentage format (3% or 0.03) in formulas
- Test one formula, then copy it to other cells (adjust references as needed)
- For "Best Card", use: `=IF(C2=MAX(C2:E2),"Card A",IF(D2=MAX(C2:E2),"Card B","Card C"))`
- Alternative: Create a helper column with MAX values, then match card names
- Format dollar amounts as currency for clarity

## Real-World Context

This task represents a common personal finance challenge: optimizing credit card rewards across multiple cards. Many people have 2-3 credit cards but don't know which to use for which purchases. This spreadsheet becomes a practical reference tool that maximizes cashback returns.