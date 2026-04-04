# Utility Bill Analysis Task

**Difficulty**: 🟡 Medium  
**Skills**: Date arithmetic, formulas, conditional formatting, data analysis  
**Duration**: 180 seconds  
**Steps**: ~50

## Objective

Perform practical data analysis on real-world utility billing data containing common messiness: inconsistent billing periods, estimated meter readings, and irregular dates. Calculate meaningful metrics (month-over-month changes, average daily usage) and apply conditional formatting to identify anomalies.

## Task Description

The agent must:
1. Open a pre-loaded utility bill spreadsheet with 12 months of data
2. Calculate days between consecutive billing dates
3. Calculate average daily usage (kWh per day)
4. Calculate month-over-month percentage change in usage
5. Flag or highlight estimated readings
6. Apply conditional formatting to identify high-usage periods (>30 kWh/day)
7. Save the analyzed file

## Data Structure

The spreadsheet contains columns:
- **Bill Date**: Date of bill (varies, 28-34 day periods)
- **Usage (kWh)**: Monthly electricity usage
- **Bill Amount ($)**: Total bill amount
- **Reading Type**: "Actual" or "Estimated"

## Expected Results

Agent should add calculated columns:
- **Days in Period**: Days between consecutive bills
- **Daily Avg (kWh/day)**: Usage divided by days in period
- **Usage Change (%)**: Month-over-month percentage change
- **Conditional formatting**: High usage days highlighted

## Verification Criteria

1. ✅ **Days Calculated**: Days between billing dates correctly computed for all rows
2. ✅ **Daily Usage Formulas**: Daily average usage correctly calculated (usage / days)
3. ✅ **Percentage Changes**: Month-over-month changes calculated accurately
4. ✅ **First Row Handled**: Edge case for first month handled without errors
5. ✅ **Conditional Formatting Applied**: High-usage months highlighted
6. ✅ **Estimated Readings Flagged**: Rows with estimated readings identifiable
7. ✅ **Number Formatting**: Currency and percentages formatted appropriately
8. ✅ **Peak Usage Identifiable**: Highest consumption period clearly visible

**Pass Threshold**: 75% (requires at least 6 out of 8 criteria)

## Skills Tested

- Date arithmetic (calculating days between dates)
- Formula creation (division, percentage calculations)
- Conditional formulas (IF statements for edge cases)
- Conditional formatting application
- Data quality assessment (handling estimated readings)
- Column insertion and management
- Cell reference management (absolute vs relative)
- Number and percentage formatting

## Real-World Context

This simulates a frustrated homeowner trying to understand why their electricity bill keeps increasing. The data contains typical utility billing messiness:
- Estimated readings when meter wasn't accessible
- Varying billing periods (not exactly 30 days)
- Seasonal usage patterns (higher in summer due to AC)
- Need to normalize data for fair comparison

## Setup

The setup script:
- Creates realistic utility bill CSV data (12 months)
- Opens the file in LibreOffice Calc
- Focuses and maximizes the window

## Export

The export script:
- Saves the analyzed file as `/home/ga/Documents/utility_analysis.ods`
- Closes LibreOffice Calc

## Verification

Verifier checks:
1. Presence and correctness of calculated columns
2. Formula accuracy for days, daily averages, and percentage changes
3. Edge case handling (first row with no previous date)
4. Conditional formatting rules applied
5. Number formatting (currency, percentages)
6. Identification of peak usage period