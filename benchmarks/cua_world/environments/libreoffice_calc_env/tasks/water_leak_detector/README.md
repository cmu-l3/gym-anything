# Water Leak Detection Task

**Difficulty**: 🟡 Medium  
**Skills**: Time-series analysis, rolling averages, conditional logic, anomaly detection  
**Duration**: 240 seconds  
**Steps**: ~15

## Objective

Analyze household water usage data to identify potential leaks or wasteful consumption patterns. Use rolling averages to establish baseline consumption, calculate anomaly thresholds, flag suspicious days, and quantify water waste and cost impact.

## Task Description

A homeowner suspects a leak after receiving an unexpectedly high water bill. They have 30 days of daily water meter readings but need help identifying which days show genuinely anomalous usage that warrant investigation.

The agent must:
1. Import the water usage CSV data
2. Calculate a 7-day rolling average baseline for each day
3. Define anomaly threshold as 150% of baseline (baseline × 1.5)
4. Flag days where actual usage exceeds threshold
5. Calculate excess water wasted on anomalous days
6. Create summary statistics (optional)

## Expected Results

### Columns Required:
- **A: Date** (from CSV)
- **B: Gallons** (from CSV, daily usage)
- **C: 7-Day Avg Baseline** - Rolling average of previous 7 days
- **D: Threshold** - Baseline × 1.5
- **E: Leak Alert?** - "POTENTIAL LEAK" if usage exceeds threshold
- **F: Excess Gallons** - Amount wasted above baseline (0 if below threshold)

### Formulas (starting at row 8, first row with 7 days of history):
- **C8**: `=AVERAGE(B2:B8)` (then copy down to C31)
- **D8**: `=C8*1.5` (then copy down to D31)
- **E8**: `=IF(B8>D8,"POTENTIAL LEAK","")` (then copy down to E31)
- **F8**: `=IF(B8>D8,B8-C8,0)` (then copy down to F31)

### Summary Statistics (optional but recommended):
Place in cells starting around A34:
- **Total Leak Days**: `=COUNTIF(E8:E31,"POTENTIAL LEAK")`
- **Total Excess Water**: `=SUM(F8:F31)`
- **Estimated Cost**: `=SUM(F8:F31)*0.01` (assumes $0.01/gallon)

## Verification Criteria

1. ✅ **File Created**: `water_analysis.ods` exists and is valid
2. ✅ **Columns Present**: All 6 required columns exist with data
3. ✅ **Rolling Average Formula**: Correctly uses AVERAGE with 7-row ranges in 90%+ rows
4. ✅ **Threshold Formula**: Correctly multiplies baseline by 1.5 in 90%+ rows
5. ✅ **Leak Detection Logic**: IF statement correctly flags high usage in 90%+ rows
6. ✅ **Excess Calculation**: Correctly calculates water wasted
7. ✅ **Reasonable Results**: 4-9 leak days detected, 200-600 gallons total excess

**Pass Threshold**: 70% (requires core formulas correct and reasonable leak detection)

## Skills Tested

- CSV import and data handling
- Rolling window calculations (time-series analysis)
- Relative cell references (B2, C8) vs absolute ($B$2)
- Nested IF statements
- Threshold-based anomaly detection
- AVERAGE, IF, COUNTIF, SUM functions
- Data cleaning (handling zeros/nulls)
- Formula propagation across rows

## Real-World Context

This task represents practical environmental and financial problem-solving:
- Water leaks waste billions of gallons annually
- Early detection saves money and conserves resources
- Statistical analysis distinguishes normal variation from genuine problems
- Skills transfer to energy monitoring, expense tracking, health metrics analysis

## Tips

- Import CSV via File → Open, select water_usage_data.csv
- First 7 rows (2-7) don't have enough history for rolling average
- Start calculations in row 8 (first row with 7 prior days)
- Copy formulas down to row 31 (last day of data)
- Use Ctrl+D to fill formulas down after selecting range
- Conditional formatting can highlight leak days visually (optional)
- Save as water_analysis.ods when complete