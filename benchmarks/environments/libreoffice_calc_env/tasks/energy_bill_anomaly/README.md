# LibreOffice Calc Energy Bill Analysis Task (`energy_bill_anomaly@1`)

**Difficulty**: 🟡 Medium  
**Skills**: Data entry, formula creation, percentage calculations, conditional highlighting  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Analyze household energy bills across 6 months to identify cost anomalies. Create a structured table, enter historical billing data, calculate key metrics (cost per kWh, averages, percentage deviations), and visually highlight the anomalous billing period. This represents a common real-world scenario where users investigate unexpected utility cost spikes.

## Task Description

You received a shockingly high electricity bill and want to analyze the past 6 months to identify the problem. The agent must:

1. Create a table with column headers:
   - A1: "Month"
   - B1: "kWh Usage"
   - C1: "Total Cost"
   - D1: "Cost per kWh"
   - E1: "% vs Average"

2. Enter 6 months of billing data (rows 2-7):
   - January: 850 kWh, $102.00
   - February: 780 kWh, $93.60
   - March: 820 kWh, $98.40
   - April: 890 kWh, $106.80
   - May: 1420 kWh, $170.40 (THE ANOMALY!)
   - June: 810 kWh, $97.20

3. Calculate Cost per kWh (Column D):
   - D2: =C2/B2 (copy down to D7)
   - Format as currency with 4 decimal places

4. Calculate Average Usage:
   - Add "Average:" label in B8 or nearby
   - Calculate =AVERAGE(B2:B7) (should be ~928 kWh)

5. Calculate Percentage vs Average (Column E):
   - E2: =(B2-$B$9)/$B$9*100 (copy down to E7)
   - Shows how much each month deviates from average

6. Highlight the Anomaly:
   - Identify May (Row 6) as the outlier (~50% above average)
   - Apply background color (yellow, red, orange, etc.) to entire row A6:E6

7. Save the file

## Expected Results

- **Data Entry**: All 6 months with correct usage and cost values
- **Cost per kWh**: ~$0.12 consistently across all months
- **Average Usage**: ~928 kWh
- **May Deviation**: ~53% above average
- **Visual Highlight**: May row (Row 6) has background color applied

## Verification Criteria

1. ✅ **Data Entry Complete**: All 6 months entered correctly (±$1, ±5 kWh tolerance)
2. ✅ **Cost per kWh Calculated**: Column D has division formulas (~$0.12 per kWh)
3. ✅ **Average Computed**: Average usage calculated (~928 kWh)
4. ✅ **Percentage Deviations**: Column E shows correct percentage differences
5. ✅ **Anomaly Identified**: May shows ~50%+ deviation in calculations
6. ✅ **Visual Highlighting**: Anomalous row has background color applied
7. ✅ **Formula Integrity**: Formulas use cell references, not hardcoded values

**Pass Threshold**: 75% (5/7 criteria must pass)

## Skills Tested

- Structured data entry with headers
- Division formulas with cell references
- Statistical functions (AVERAGE)
- Percentage calculations with absolute references ($B$9)
- Formula copying (relative vs absolute references)
- Anomaly detection through calculation
- Visual formatting (background colors)
- Financial/utility analysis

## Tips

- Use Tab or Enter to move between cells efficiently
- Start formulas with `=` sign
- Use absolute reference ($B$9) for average in percentage formulas
- Copy formulas by selecting cell and dragging fill handle down
- Apply background color: Select row → Format → Cells → Background tab
- Alternative: Right-click row → Format Cells → Background