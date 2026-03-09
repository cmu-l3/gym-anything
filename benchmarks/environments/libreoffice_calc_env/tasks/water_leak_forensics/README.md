# LibreOffice Calc Water Leak Forensic Analyzer Task (`water_leak_forensics@1`)

## Overview

This task simulates a **real-world environmental monitoring and anomaly detection scenario**: a frustrated homeowner has received a water bill that's 3× their normal amount and suspects a hidden leak somewhere in their plumbing system. They've been manually recording daily water meter readings for the past two months but haven't analyzed the data yet. The agent must import this messy data, calculate daily usage, identify the anomaly pattern, pinpoint when the leak likely started, estimate total water waste, and calculate the financial cost of the leak.

**Difficulty**: 🟡 Medium  
**Skills**: Data analysis, formula creation, anomaly detection, financial calculation  
**Duration**: 300 seconds (5 minutes)  
**Steps**: ~50

## Scenario

**The Situation**: Sarah, a homeowner, just received her bimonthly water bill: **$487** instead of the usual **$160**. She suspects a leak but doesn't know where or when it started. For the past 60 days, she's been manually recording her water meter reading each evening (though she missed a few days when traveling). The data is in a CSV file—it's messy, with inconsistent date formatting.

**The Goal**: Help Sarah determine:
1. What her normal daily water usage was before the leak
2. When the leak likely started (specific date)
3. How much water has been wasted since the leak began
4. The financial cost of the wasted water at $0.0045 per gallon

## Required Actions

### 1. Data Import and Cleaning
- Open `/home/ga/Documents/water_meter_readings.csv` in LibreOffice Calc
- Add column headers: Date, Meter_Reading_Gallons, Daily_Usage, etc.
- Handle mixed date formats (some MM/DD/YYYY, some M/D/YY)

### 2. Calculate Daily Usage
- Create formulas to calculate daily water usage (current reading - previous reading)
- Apply formula to all rows with valid consecutive readings
- Expected pattern: ~85-95 gallons/day initially, then jump to ~300+ gallons/day

### 3. Establish Baseline
- Calculate average daily usage from first 20 days (pre-leak period)
- Store baseline value for comparison
- Expected baseline: approximately 85-95 gallons/day

### 4. Detect Anomaly
- Compare each day's usage to baseline
- Identify when usage consistently exceeds 150% of baseline
- Pinpoint specific date when leak pattern begins (around day 22-24)

### 5. Calculate Water Waste
- For each day after leak starts, calculate excess water used beyond baseline
- Sum total wasted water
- Expected total: approximately 6,000-8,000 gallons over ~38 days

### 6. Calculate Financial Cost
- Multiply total wasted water by cost per gallon ($0.0045)
- Apply currency formatting
- Expected cost: approximately $27-$36

### 7. Create Summary Report
- Build summary section with key findings:
  - Normal daily usage
  - Leak start date
  - Days with leak active
  - Total water wasted
  - Financial cost
  - Current leak rate

### 8. Save Analysis
- Save file as `/home/ga/Documents/results/water_leak_analysis.ods`

## Success Criteria

The task is graded on 8 criteria:

1. ✅ **Data Imported**: 55+ rows of meter readings present
2. ✅ **Daily Usage Calculated**: Formulas computing usage differences
3. ✅ **Baseline Established**: Average of first ~20 days (75-110 gal/day)
4. ✅ **Leak Date Identified**: Specific date around day 22-24 identified
5. ✅ **Waste Quantified**: Total excess water calculated (5,000-9,000 gallons)
6. ✅ **Cost Calculated**: Financial impact computed ($22.50-$40.50)
7. ✅ **Summary Report**: Key findings clearly presented with labels
8. ✅ **Formulas Used**: Calculations use formulas, not manual entry

**Pass Threshold**: 75% (requires 6 out of 8 criteria)

## Skills Tested

### Technical Skills
- CSV file import and parsing
- Data cleaning (handling inconsistent formats)
- Multi-step formula creation
- Cell reference management (absolute vs. relative)
- Conditional logic (IF statements)
- Statistical functions (AVERAGE, SUM)
- Financial calculations
- Data formatting and presentation

### Analytical Skills
- Time-series data analysis
- Baseline establishment
- Anomaly detection logic
- Pattern recognition
- Root cause timing identification
- Quantitative reasoning
- Actionable insight generation

## Tips

**Formula Hints:**
- Daily usage: `=B3-B2` (current meter reading - previous reading)
- Baseline: `=AVERAGE(C2:C21)` (average of first 20 daily usage values)
- Usage ratio: `=C3/$F$2` (daily usage / baseline, using absolute reference)
- Waste per day: `=IF(C3>$F$2, C3-$F$2, 0)` (only count excess above baseline)
- Total waste: `=SUM(E23:E60)` (sum from leak start to end)
- Cost: `=F5*0.0045` (waste gallons × cost per gallon)

**Analysis Hints:**
- Normal residential usage: 80-100 gallons/day per person
- Leak indicator: Sustained usage >150% of baseline for 3+ consecutive days
- A running toilet wastes ~200 gallons/day
- A dripping faucet wastes ~15-20 gallons/day
- Underground leaks can waste 200-400+ gallons/day

**Workflow Hints:**
- Work in stages: import → calculate → analyze → summarize
- Use column headers to keep organized
- Put summary at top (rows 1-8) for easy visibility
- Use cell references instead of typing numbers multiple times
- Format currency cells for readability

## Real-World Relevance

This task represents authentic spreadsheet usage where:
- **Data is imperfect**: Inconsistent formats, no headers, manual collection
- **Problem requires insight**: Raw meter numbers are meaningless without analysis
- **Multiple analytical steps**: Can't solve with single formula—requires reasoning
- **Financial stakes**: Real money being wasted, creates urgency
- **Actionable output needed**: Analysis must support decisions (when to call plumber, how urgent)
- **Domain knowledge helps**: Understanding residential water patterns improves analysis

**Common real-world variations:**
- Electricity usage anomaly (faulty appliance, crypto mining malware)
- Natural gas leak detection
- Internet data usage forensics
- Inventory shrinkage detection
- Health metric anomaly detection (blood pressure, glucose patterns)

## Expected Results

**Data Structure:**