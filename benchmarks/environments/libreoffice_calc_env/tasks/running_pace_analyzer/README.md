# Running Pace Analyzer Task

**Difficulty**: 🟡 Medium  
**Skills**: Data cleaning, time calculations, unit conversions, formula creation, conditional formatting  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Clean and analyze messy running training log data by standardizing formats, calculating pace metrics, and identifying performance trends. This task simulates a common real-world scenario where athletes need to make sense of data collected from various sources.

## Task Description

The agent must:
1. Open a running training log spreadsheet with inconsistent data formats
2. Create a "Distance_Miles" column converting all distances to miles
3. Create a "Time_Minutes" column converting all time formats to decimal minutes
4. Calculate "Pace_MinPerMile" (minutes per mile) for each run
5. Apply conditional formatting to highlight fastest paces
6. Calculate average pace by run type (Easy, Tempo, Long)
7. Save the analyzed file

## Data Characteristics

**Messy Real-World Data Includes:**
- Time formats: HH:MM:SS (e.g., "01:05:30"), decimal minutes (e.g., "65.5"), decimal hours (e.g., "1.0917")
- Distance units: Mix of miles and kilometers
- Missing data: Some runs lack elevation gain information
- Run types: Easy, Tempo, Long runs requiring separate analysis

## Expected Results

**New Columns Created:**
- **Distance_Miles**: All distances converted to miles (km × 0.621371)
- **Time_Minutes**: All times converted to decimal minutes
- **Pace_MinPerMile**: Calculated pace (Time_Minutes ÷ Distance_Miles)

**Analysis:**
- Average pace calculated for each run type
- Conditional formatting applied to pace column
- All formulas (not hardcoded values)

## Verification Criteria

1. ✅ **Distance Standardized**: Distance_Miles column with correct conversions
2. ✅ **Time Standardized**: Time_Minutes column handling all format types
3. ✅ **Pace Calculated**: Pace_MinPerMile with accurate formulas
4. ✅ **Formulas Correct**: Conversion formulas syntactically valid
5. ✅ **Summary Analysis**: Average paces by run type calculated
6. ✅ **Visual Highlighting**: Conditional formatting applied
7. ✅ **Data Quality**: No errors, paces within realistic bounds (5-15 min/mile)

**Pass Threshold**: 70% (5/7 criteria must pass)

## Skills Tested

- Complex formula creation with nested IF statements
- Time arithmetic and format parsing
- Unit conversion mathematics
- Cell references (absolute vs. relative)
- Conditional formatting application
- AVERAGE/AVERAGEIF functions
- Data quality validation

## Tips

- Use IF statements to handle different time formats
- Formula for time conversion: `=IF(E2="HH:MM:SS", HOUR(D2)*60+MINUTE(D2)+SECOND(D2)/60, IF(E2="DecimalMinutes", D2, D2*60))`
- Formula for distance conversion: `=IF(C2="km", B2*0.621371, B2)`
- Pace calculation: `=Time_Minutes/Distance_Miles`
- Use AVERAGEIF to calculate averages by run type
- Conditional formatting: Format → Conditional Formatting → Condition