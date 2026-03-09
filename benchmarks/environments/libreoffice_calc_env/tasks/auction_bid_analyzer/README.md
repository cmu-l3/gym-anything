# Online Auction Bid Strategy Analyzer Task

**Difficulty**: 🟡 Medium  
**Skills**: Data cleaning, conditional formulas, financial analysis, percentage calculations  
**Duration**: 240 seconds  
**Steps**: ~15

## Objective

Clean and analyze messy auction bidding data to understand spending patterns, success rates, and identify emotional bidding behaviors. This task simulates real-world personal finance analytics where users need to make sense of inconsistent data exported from multiple online auction platforms.

## Scenario

Jamie is an online auction enthusiast who collects vintage cameras and watches. After 3 months of bidding, they've exported their bidding history but the data is messy with inconsistent formatting, duplicate entries, and missing values. Jamie wants to understand:
- Overall win rate (% of auctions won)
- Total money spent (including shipping)
- Success by category
- Whether they're "emotional bidding" (bidding too close to their maximum comfortable price)

## Task Description

The agent must:
1. Open the provided `auction_data.csv` file
2. Clean the data (standardize categories, handle duplicates)
3. Create a `Total_Cost` column (Your_Bid + Shipping_Cost, handling blanks)
4. Calculate overall win rate as a percentage
5. Create a `Bid_Ratio` column (Your_Bid / Max_Comfortable_Bid)
6. Flag high-risk bids where Bid_Ratio >= 0.8
7. Calculate total spending for won items only
8. Save the analysis

## Data Issues to Handle

- **Inconsistent categories**: "Camera", "camera", "CAMERA", "watch", "Watch", "WATCH"
- **Duplicate entries**: Same Item_ID appearing multiple times (keep first occurrence)
- **Missing shipping costs**: Some cells are blank (treat as $0)
- **Mixed outcomes**: "WON" vs "LOST" text

## Expected Results

### Data Cleaning
- Categories standardized (all uppercase or all lowercase)
- Duplicate Item_IDs removed
- Total_Cost = Your_Bid + Shipping_Cost (or Your_Bid if shipping blank)

### Analysis Metrics
- **Win Rate**: Formula-based calculation = (Count of "WON" / Total bids) × 100
  - Place in summary area (e.g., cell K2 or similar visible location)
- **Bid Ratio**: Your_Bid / Max_Comfortable_Bid for each item
- **High-Risk Flagging**: Items with Bid_Ratio >= 0.8 visually marked
- **Total Spending**: Sum of Total_Cost for won items only

## Verification Criteria

1. ✅ **Categories Standardized**: ≥95% in consistent format (all uppercase or lowercase)
2. ✅ **Total Cost Calculated**: Column exists with bid + shipping sum
3. ✅ **Win Rate Computed**: Formula present with value 0-100%
4. ✅ **Bid Ratio Present**: Column with Your_Bid / Max_Comfortable_Bid
5. ✅ **High-Risk Flagging**: Bid_Ratio >= 0.8 items marked/highlighted
6. ✅ **Total Spending Correct**: Sum of won items (±5% tolerance)
7. ✅ **No Duplicates**: Each Item_ID appears once
8. ✅ **Formulas Used**: Key metrics use formulas, not hardcoded values

**Pass Threshold**: 75% (6/8 criteria must pass)

## Skills Tested

- Data cleaning and standardization (UPPER/LOWER, TRIM functions)
- Conditional formulas (IF, COUNTIF, SUMIF)
- Percentage calculations
- Financial analysis
- Handling missing data
- Duplicate detection
- Conditional formatting or helper columns
- Named ranges (optional)

## CSV Data Structure
