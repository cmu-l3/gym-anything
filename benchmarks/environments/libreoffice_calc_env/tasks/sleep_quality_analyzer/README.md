# Sleep Quality Analyzer Task

**Difficulty**: 🟡 Medium  
**Skills**: CSV import, time calculations, formulas, conditional formatting, statistical analysis  
**Duration**: 180 seconds (3 minutes)  
**Steps**: ~50

## Objective

Import sleep tracking data from a CSV file, calculate sleep metrics (efficiency, average duration, deficit count), and apply conditional formatting to highlight problematic nights. This task tests data import, formula creation, statistical functions, and visual data highlighting for health analysis.

## Task Description

The agent must:
1. Open the provided `sleep_data.csv` file in LibreOffice Calc
2. Review the sleep tracking data (14 nights over 2 weeks)
3. Create a new column "Sleep Efficiency (%)" that calculates: (Time Asleep / Time in Bed) × 100
4. Apply the efficiency formula to all data rows
5. Calculate the average sleep duration using the AVERAGE function
6. Count nights with insufficient sleep (<7 hours) using COUNTIF
7. Apply conditional formatting to highlight nights with <7 hours of sleep (red background/text)
8. Save the completed analysis

## Data Structure

The CSV contains:
- **Date**: Date of sleep session
- **Bedtime**: Time went to bed
- **Wake Time**: Time woke up
- **Time in Bed (hrs)**: Total hours in bed
- **Time Asleep (hrs)**: Actual sleep duration
- **Caffeine After 2pm**: Y/N whether consumed caffeine after 2pm
- **Screen Time Before Bed (mins)**: Minutes of screen time before sleeping

## Expected Results

- **Column H (or next available)**: Sleep Efficiency (%) = (Time Asleep / Time in Bed) × 100
- **Summary cell**: Average Sleep = AVERAGE of Time Asleep column ≈ 6.8 hours
- **Summary cell**: Nights <7 hours = COUNTIF count = 5 nights
- **Conditional Formatting**: Time Asleep column cells with <7 hours highlighted in red

## Verification Criteria

1. ✅ **CSV Data Imported**: All 14 rows with correct values present
2. ✅ **Sleep Efficiency Formula**: Formula pattern =(E/D)*100 in calculated column
3. ✅ **Average Sleep Accurate**: AVERAGE function used, result ≈ 6.8 ± 0.2 hours
4. ✅ **Poor Sleep Count Correct**: COUNTIF formula returns 5 nights
5. ✅ **Conditional Formatting Applied**: Time Asleep column has threshold-based formatting
6. ✅ **Formula Consistency**: Efficiency formula applied to all 14 data rows
7. ✅ **No Calculation Errors**: No #DIV/0!, #VALUE!, or #REF! errors

**Pass Threshold**: 70% (5/7 criteria must pass)

## Skills Tested

- CSV file import and data integrity
- Time/duration calculations
- Percentage formula creation
- Statistical functions (AVERAGE, COUNTIF)
- Conditional formatting with threshold rules
- Formula copying and relative references
- Data analysis and pattern recognition
- Health metrics understanding

## Real-World Context

This task simulates analyzing sleep tracker data (from Fitbit, Apple Watch, WHOOP, etc.) to identify:
- Poor sleep efficiency (wasted time in bed)
- Insufficient sleep duration (<7 hours recommended)
- Patterns correlating lifestyle factors (caffeine, screen time) with sleep quality

The insights help users make behavioral changes to improve sleep health.

## Setup

The setup script:
- Creates realistic `sleep_data.csv` with 14 nights of tracking data
- Launches LibreOffice Calc with a new blank spreadsheet
- Focuses and maximizes the window
- User must manually open the CSV file

## Export

The export script:
- Saves the file as `/home/ga/Documents/sleep_analysis_complete.ods`
- Closes LibreOffice Calc

## Verification

Verifier checks:
1. Data import integrity (specific cell values match CSV)
2. Sleep efficiency formula structure and calculation accuracy
3. Average sleep calculation using AVERAGE function
4. COUNTIF formula for insufficient sleep nights
5. Conditional formatting rule existence and application
6. Formula consistency across all data rows
7. Absence of formula errors

## Tips

- Use File → Open to import the CSV file from `/home/ga/Documents/`
- Create the Sleep Efficiency column in column H (or next available column)
- Formula pattern: `=(E3/D3)*100` (adjust row numbers as needed)
- Copy formula down using Ctrl+D or fill handle
- Place summary statistics below the data or in a designated summary area
- Apply conditional formatting: Select range → Format → Conditional Formatting → Condition
- Set condition: "Cell value is less than 7" with red background/text