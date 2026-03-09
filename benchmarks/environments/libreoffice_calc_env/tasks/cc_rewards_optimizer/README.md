# Credit Card Rewards Optimization Task

**Difficulty**: 🟡 Medium  
**Skills**: Multi-sheet references, lookup functions, conditional logic, financial calculations  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Analyze past credit card transactions to determine optimal card usage for maximum rewards, and calculate the opportunity cost of suboptimal card choices. This task tests multi-table data analysis, lookup formulas, and financial decision support capabilities.

## Task Description

The agent must:
1. Review and fix transaction categories in the Transactions sheet
2. Add an "Optimal_Card" column that identifies which card should have been used
3. Calculate actual rewards earned and optimal rewards possible for each transaction
4. Calculate opportunity cost (money left on the table)
5. Create summary analysis showing total opportunity cost
6. Build a category-to-card recommendation table for future purchases

## Starting State

The spreadsheet opens with three sheets:
- **Transactions**: 35 transactions with some missing/incorrect categories
- **Card_Details**: 4 credit cards with reward rates by category
- **Analysis**: Empty sheet for calculations

## Data Structure

### Transactions Sheet
- Columns: Date, Merchant, Amount, Card_Used, Category
- Some categories are blank or miscategorized
- Categories: Groceries, Gas, Dining, Travel, General

### Card_Details Sheet
- Rows: 4 credit cards
- Columns: Card_Name, Groceries, Gas, Dining, Travel, General
- Values: Reward percentages (e.g., 5%, 2%, 1%)

## Required Actions

1. **Clean Categories**: Fix blank and incorrect categories in Transactions
2. **Add Optimal_Card Column**: Use lookup formulas to find best card for each category
3. **Calculate Rewards**:
   - Actual_Rewards = Amount × Actual card's rate for that category
   - Optimal_Rewards = Amount × Best card's rate for that category
   - Opportunity_Cost = Optimal - Actual
4. **Create Summary** in Analysis sheet:
   - Total Actual Rewards
   - Total Optimal Rewards
   - Total Opportunity Cost
   - Capture Rate percentage
5. **Build Recommendation Table**: Category → Best Card mapping

## Success Criteria

1. ✅ **All Transactions Categorized**: No empty category cells
2. ✅ **Optimal Card Identified**: Optimal_Card column with valid card names
3. ✅ **Calculations Correct**: Spot-check of reward calculations shows accuracy
4. ✅ **Summary Analysis Present**: Analysis sheet has totals and capture rate
5. ✅ **Recommendation Table Exists**: Category-to-card mapping complete
6. ✅ **Formula-Based**: Calculations use formulas, not hard-coded values

**Pass Threshold**: 85% (5 out of 6 criteria)

## Skills Tested

- Multi-sheet navigation and references
- VLOOKUP/INDEX-MATCH formulas
- Conditional logic (IF statements)
- Data categorization and cleaning
- Financial calculations
- Summary table creation
- Decision matrix building

## Tips

- Review the Card_Details sheet to understand reward structures
- Common categories: Groceries, Gas, Dining, Travel, General
- Use VLOOKUP or INDEX-MATCH to find reward rates
- MAX function can help find the best reward rate
- Absolute references ($) are important for lookup tables
- The Analysis sheet should summarize findings and provide actionable recommendations

## Example Calculations

For a $100 grocery purchase:
- If used Chase Freedom (5% groceries): $5.00 reward
- If used Citi Double Cash (2% everything): $2.00 reward  
- Opportunity Cost: $3.00 (missed by not using optimal card)