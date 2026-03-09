# Meal Kit Value Calculator Task

**Difficulty**: 🟡 Medium
**Skills**: Formula creation, data analysis, cost comparison, averaging
**Duration**: 180 seconds (3 minutes)
**Steps**: ~30

## Objective

Analyze the true cost-effectiveness of meal kit subscriptions versus traditional grocery shopping by calculating per-serving costs adjusted for food waste, then determine which option provides better value.

## Task Description

**Scenario**: Maria has been using a meal kit service for 3 months but her partner thinks they're "wasting money." She tracked both meal kit deliveries and a comparison week where she cooked the same recipes from grocery store ingredients. Now she needs to calculate the REAL cost difference accounting for:
- Perfectly portioned meal kit ingredients (minimal waste)
- Grocery shopping waste (that bag of cilantro where she used 2 tablespoons and threw away the rest)
- Monthly subscription fees
- Varying serving sizes

The agent must perform multi-factor cost analysis to settle the household debate with data.

## Starting State

- LibreOffice Calc opens with CSV file containing meal comparison data
- Data includes: Source (MealKit/Grocery), Date, Meal Name, Total Cost, Servings, Waste Percent
- 12 meal entries (6 meal kit, 6 grocery) plus subscription fee information

## Data Structure

| Source | Date | Meal_Name | Total_Cost | Servings | Waste_Percent |
|--------|------|-----------|------------|----------|---------------|
| MealKit | 2024-01-05 | Chicken Teriyaki | 11.99 | 2 | 0.05 |
| Grocery | 2024-01-15 | Chicken Teriyaki | 8.47 | 2 | 0.30 |
| ... | ... | ... | ... | ... | ... |

## Required Actions

### Step 1: Calculate Per-Serving Costs
- Create new column (e.g., column G) for "Per Serving Cost"
- Formula: `=D2/E2` (Total Cost / Servings)
- Copy formula down for all meal entries

### Step 2: Adjust for Food Waste
- Create column (e.g., column H) for "Waste Adjusted Cost"
- For grocery items: `=D2/(1-F2)` (accounts for thrown-away food)
- For meal kit items: `=D2` (minimal waste already factored in)
- Create column (e.g., column I) for "Waste Adjusted Per Serving"
- Formula: `=H2/E2`

### Step 3: Calculate Averages
- Use AVERAGE function to calculate mean waste-adjusted per-serving cost for meal kit entries
- Use AVERAGE function to calculate mean waste-adjusted per-serving cost for grocery entries
- Suggested location: Rows 15-20 in a summary section

### Step 4: Factor Subscription Fee
- Monthly subscription fee is provided in data ($9.99/month typical)
- Calculate per-serving subscription cost (divide by number of meal kit servings)
- Add to meal kit average for complete cost picture

### Step 5: Calculate Cost Difference
- Subtract grocery average from meal kit average (or vice versa)
- Calculate percentage difference: `=(Difference / Grocery Average) * 100`

### Step 6: Format Results
- Apply currency format ($) to all dollar amounts
- Apply percentage format (%) to waste percentages and differences
- Create clear summary section with labels

### Step 7: Save File
- Save as ODS format

## Expected Results Summary Section

Your analysis should show something like:
- **Meal Kit Avg (per serving)**: ~$7.50-$8.50
- **Grocery Avg (per serving)**: ~$6.50-$7.50 (after waste adjustment)
- **Absolute Difference**: $X.XX per serving
- **Percentage Difference**: X% more expensive
- **Monthly Cost Difference** (optional): $XX.XX

## Success Criteria

1. ✅ **Per-Serving Formulas Present**: All meals have cost-per-serving calculations
2. ✅ **Waste Adjustment Applied**: Grocery costs adjusted for food waste (formula detected)
3. ✅ **Averages Calculated**: AVERAGE functions used for both meal kit and grocery data
4. ✅ **Subscription Fees Included**: Monthly fees factored into meal kit average
5. ✅ **Cost Difference Computed**: Absolute and percentage differences calculated
6. ✅ **Values Within Expected Range**: All calculations produce reasonable real-world values
7. ✅ **Proper Formatting**: Currency and percentage formats applied appropriately

**Pass Threshold**: 75% (requires at least 5 out of 7 criteria)

## Skills Tested

- Multi-step formula creation
- Division and arithmetic operations
- AVERAGE function usage
- Conditional logic (different waste adjustments for different sources)
- Data normalization (per-serving costs)
- Percentage calculations
- Number formatting (currency, percentages)
- Cost-benefit analysis

## Tips

- Select waste-adjusted per-serving costs when calculating averages (not raw costs)
- Grocery waste percentages are higher (15-35%) than meal kit waste (5-10%)
- Subscription fee appears as a separate line item in the data
- Use absolute cell references ($A$1) when needed for subscription fee
- Consider color-coding meal kit vs grocery rows for clarity
- Double-check that waste adjustment formula divides by (1 - waste%), not multiplies