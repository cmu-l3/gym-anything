# LibreOffice Calc Sleep Pattern Optimizer Task (`sleep_pattern_optimizer@1`)

**Difficulty**: 🟡 Medium  
**Skills**: Time arithmetic, conditional logic, statistical analysis, data cleaning, conditional formatting  
**Duration**: 300 seconds  
**Steps**: ~50

## Objective

Analyze messy sleep tracking data to identify patterns between sleep quality and contributing factors (bedtime, caffeine, screen time, exercise). Calculate optimal bedtime recommendations and apply conditional formatting to visualize patterns.

## Task Context

**Human Scenario**: A frustrated person has been logging sleep data for weeks using a basic tracking app, but the exported CSV is inconsistent and hard to interpret. They desperately want answers: "What time should I go to bed to get quality sleep?" and "Does my evening coffee really matter?" They need help making sense of their data through spreadsheet analysis.

## Task Description

The agent must:
1. Open the messy sleep log CSV in LibreOffice Calc
2. Calculate sleep duration (handling times that cross midnight)
3. Categorize sleep quality into tiers (Excellent/Good/Fair/Poor)
4. Apply conditional formatting to highlight quality patterns
5. Calculate correlation between quality and factors (caffeine, screen time, exercise)
6. Identify optimal bedtime window for best sleep quality
7. Create summary insights with formulas

## Starting Data

The CSV contains columns:
- **Date**: Date of sleep
- **Bedtime**: Time went to bed (MIXED FORMATS: "11:30 PM", "23:30", "10:15 p.m.")
- **Wake Time**: Time woke up (MIXED FORMATS)
- **Quality Score**: Subjective rating 1-10
- **Caffeine After 2PM**: Yes/No (sometimes inconsistent capitalization)
- **Screen Time (hours)**: Hours of screen time before bed
- **Exercise**: Yes/No
- **Notes**: Free-form text notes

**Data Messiness**: Time formats are inconsistent, some cells may be empty, text entries vary in capitalization.

## Required Actions

### 1. Calculate Sleep Duration
- Add new column "Hours Slept"
- Create formula: `=IF(C2<B2, C2+1-B2, C2-B2)*24` (or equivalent)
- Handle midnight crossover (bedtime 11 PM, wake 7 AM = 8 hours, not -16)

### 2. Categorize Sleep Quality
- Add column "Quality Category"
- Use IF formula to categorize:
  - "Excellent" for scores 8-10
  - "Good" for scores 7-7.9
  - "Fair" for scores 5-6.9
  - "Poor" for scores <5

### 3. Apply Conditional Formatting
- Highlight quality scores or categories:
  - Red/warm colors for Poor quality
  - Green/cool colors for Excellent quality
- Use Format → Conditional Formatting → Condition

### 4. Calculate Factor Correlations
- Create summary section with formulas:
- Average quality WITH caffeine: `=AVERAGEIF(E:E,"Yes",D:D)`
- Average quality WITHOUT caffeine: `=AVERAGEIF(E:E,"No",D:D)`
- Average quality with HIGH screen time: `=AVERAGEIF(F:F,">2",D:D)`
- Average quality with LOW screen time: `=AVERAGEIF(F:F,"<=2",D:D)`
- Average quality WITH exercise: `=AVERAGEIF(G:G,"Yes",D:D)`
- Average quality WITHOUT exercise: `=AVERAGEIF(G:G,"No",D:D)`

### 5. Identify Optimal Bedtime
- Analyze which bedtime range correlates with highest quality
- Use AVERAGEIF with time conditions
- Example: `=AVERAGEIF(B:B,">=22:00",D:D)` for bedtimes after 10 PM

## Success Criteria

1. ✅ **Sleep Duration Calculated**: Column with time arithmetic formula correctly computing hours slept
2. ✅ **Quality Categories Applied**: IF formula categorizing sleep quality into tiers
3. ✅ **Conditional Formatting Present**: Visual highlighting of good vs poor quality nights
4. ✅ **Factor Correlation Computed**: AVERAGEIF formulas analyzing caffeine, screen time, exercise impacts
5. ✅ **Optimal Bedtime Identified**: Formula-based analysis determining best bedtime window
6. ✅ **Data Standardized**: Time formats cleaned and consistent (optional bonus)

**Pass Threshold**: 70% (requires at least 4 out of 6 criteria)

## Skills Tested

- Time/date arithmetic and format handling
- Conditional logic (IF, nested IF)
- Statistical functions (AVERAGEIF, COUNTIF)
- Conditional formatting rules
- Data cleaning and standardization
- Pattern recognition and correlation analysis
- Real-world messy data handling

## Tips

- **Time arithmetic**: Use `=(wake_time - bedtime)*24` for same-day sleep
- **Midnight crossover**: Add `IF(wake<bed, wake+1-bed, wake-bed)*24`
- **AVERAGEIF syntax**: `=AVERAGEIF(range_to_check, criteria, average_range)`
- **Conditional formatting**: Select range → Format → Conditional → Color Scale or Condition
- **Summary section**: Create a clear area (e.g., rows 25-35) for correlation insights

## Expected Results

After completion:
- New column showing calculated sleep duration (e.g., 7.5, 8.0, 6.5 hours)
- Quality category labels (Excellent, Good, Fair, Poor)
- Visual color-coding of quality scores
- Summary statistics showing:
  - "Avg quality with caffeine: 6.2"
  - "Avg quality without caffeine: 7.8"
  - "Optimal bedtime range: 10:00 PM - 11:00 PM"

## Verification

The verifier checks:
1. Presence of time arithmetic formula patterns
2. Conditional logic formulas for categorization
3. Conditional formatting rules in the spreadsheet
4. AVERAGEIF or similar statistical formulas
5. Analysis of bedtime vs quality correlation
6. Overall formula sophistication and correctness