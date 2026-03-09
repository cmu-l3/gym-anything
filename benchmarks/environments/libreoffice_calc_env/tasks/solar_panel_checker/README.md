# Solar Panel Production Analyzer Task

**Difficulty**: 🟡 Medium  
**Skills**: Data cleaning, conditional logic, statistical analysis, error handling  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Analyze messy time-series energy production data from a residential solar panel system to identify potential performance issues. Import CSV data containing errors and missing values, calculate production averages, flag underperforming days, and calculate financial savings.

## Task Description

The agent must:
1. Open a CSV file containing 30 days of solar panel production data
2. Handle messy real-world data (ERROR entries, blank cells, anomalous values)
3. Calculate the average daily production, excluding invalid/error entries
4. Create a flagging system to identify days producing < 80% of average (potential panel issues)
5. Calculate total monthly production (sum of valid days only)
6. Calculate estimated electricity cost savings (@ $0.12 per kWh)
7. Count the number of problem days requiring inspection

## Starting Data Structure

CSV file with columns:
- **Date**: Calendar date (e.g., 2024-01-01)
- **Daily Production (kWh)**: Energy produced (some entries are "ERROR" or blank)
- **System Status**: Normal, ERROR, or Offline

Sample data includes:
- Normal production days: 5-8 kWh
- Error entries: "ERROR" text in numeric column
- Missing data: blank cells
- Anomalous values: 0 kWh on days that should produce energy

## Expected Results

The agent should create formulas for:
- **Average Production**: ~6-7 kWh (valid days only, excluding errors)
- **Performance Flags**: IF formula marking days below 80% threshold as "CHECK PANEL"
- **Total Production**: Sum of all valid production days (~180-210 kWh)
- **Savings**: Total production × $0.12/kWh (~$21-25)
- **Problem Count**: Number of days flagged for inspection

## Verification Criteria

1. ✅ **Average Formula Correct**: AVERAGE/AVERAGEIF formula excluding errors exists
2. ✅ **Flagging Logic Present**: IF-based formula identifies low-production days with 80% threshold
3. ✅ **Total Production Accurate**: SUM/SUMIF formula totals valid production
4. ✅ **Data Cleaning Effective**: Formulas handle error entries without breaking
5. ✅ **Savings Calculated**: Multiplication formula with $0.12 rate

**Pass Threshold**: 60% (requires 3 out of 5 criteria)

## Skills Tested

- CSV import and data inspection
- Error handling in formulas (AVERAGEIF, SUMIF, IFERROR)
- Conditional logic (IF statements with thresholds)
- Cell reference types (absolute vs relative)
- Statistical analysis (average, sum, count)
- Formula auto-fill and replication
- Number formatting (decimals, currency)

## Real-World Context

**The Frustration**: Homeowners invest $15,000+ in solar panels expecting significant electricity savings, but often lack tools to systematically verify system performance. When production seems low, they don't know if it's weather, seasonal variation, or actual equipment problems.

**The Solution**: This analysis helps identify specific days with anomalous low production, enabling targeted investigation (e.g., discovering tree shading, dirty panels, inverter issues, or sensor failures).

## Formula Hints

- **Average excluding errors**: `=AVERAGEIF(B:B,">0")` or `=AVERAGE(IF(B:B>0,B:B))`
- **Flagging underperformers**: `=IF(B2<($E$2*0.8),"CHECK PANEL","OK")` (where E2 = average)
- **Total production**: `=SUMIF(B:B,">0")`
- **Savings**: `=E3*0.12` (where E3 = total production)
- **Problem count**: `=COUNTIF(D:D,"CHECK PANEL")` (where D = flag column)

## Tips

- Scan the data first to identify error patterns
- Use AVERAGEIF or SUMIF to automatically exclude invalid entries
- Remember to use absolute references ($E$2) for the average when creating flag formulas
- Auto-fill formulas down the column for all 30 days
- Format numbers to 2 decimal places for readability