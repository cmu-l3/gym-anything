# Major Appliance Price Tracker Task

**Difficulty**: 🟡 Medium  
**Skills**: Multi-factor cost calculation, MIN functions, time-series analysis, comparative shopping  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Analyze 8 weeks of dishwasher price tracking data across 4 major retailers (Home Depot, Lowe's, Best Buy, Costco). Calculate true total costs including tax, delivery fees, and rebates. Identify the best historical price per retailer, determine the current best deal, and analyze which retailer most frequently offers the lowest price.

## Scenario

Sarah's dishwasher broke and she's been tracking the "CleanPro 5000" model for 8 weeks waiting for the best deal. Each week she recorded base price, rebates, and delivery fees for 4 retailers. Now she needs your help analyzing this data to make an informed purchase decision.

## Task Description

The agent must:
1. Open the provided CSV with 32 rows of price tracking data (8 weeks × 4 retailers)
2. Create a "Total Cost" column (G) with formula: `(Base_Price * 1.07) + Delivery_Fee - Rebate`
3. Identify the best historical price each retailer has offered (use MIN/MINIFS)
4. Determine which retailer has the best deal in Week 8 (current week)
5. Count how many weeks each retailer had the lowest price overall
6. Save the analysis

## Data Structure

| Week | Date | Retailer | Base_Price | Delivery_Fee | Rebate | Total_Cost (calculated) |
|------|------|----------|-----------|--------------|--------|------------------------|
| 1 | 2024-01-07 | Home Depot | 899.00 | 79.99 | 0.00 | =FORMULA |
| 1 | 2024-01-07 | Lowes | 879.00 | 89.99 | 25.00 | =FORMULA |
| ... | ... | ... | ... | ... | ... | ... |

## Expected Results

- **Column G (Total Cost)**: Formula `=(D2*1.07)+E2-F2` applied to all 32 data rows
- **Total Cost Values**: Should range $750-$1150
- **Historical Best Prices**: MIN value per retailer across all weeks
- **Current Best Deal**: Minimum Total Cost in Week 8
- **Frequency Analysis**: Count of wins per retailer (should sum to 8)

## Verification Criteria

1. ✅ **Total Cost Column Exists**: Column G with calculated values for all rows
2. ✅ **Formula Correct**: Sample cells show accurate calculations (±$1 tolerance)
3. ✅ **Historical Minimums Identified**: Best prices per retailer correct (±$2)
4. ✅ **Current Best Deal Correct**: Week 8 minimum identified with right retailer
5. ✅ **Frequency Count Accurate**: Win counts per retailer correct (±1)

**Pass Threshold**: 80% (4/5 criteria must pass)

## Skills Tested

- Multi-part arithmetic formulas
- Percentage calculations (7% sales tax)
- MIN/MINIFS functions
- Conditional logic (IF functions)
- COUNTIF for frequency analysis
- Cell reference management
- Time-series data analysis
- Comparative analysis across dimensions

## Tips

- Total Cost = Base Price × 1.07 (for 7% tax) + Delivery Fee - Rebate
- Use MINIFS to find minimum cost per retailer: `=MINIFS($G:$G, $C:$C, "Home Depot")`
- Week 8 data is in rows 29-32 (assuming header in row 1)
- Use COUNTIF to count weekly wins
- Some weeks may have missing data for retailers (out of stock)