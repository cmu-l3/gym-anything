# Houseplant Propagation Success Analyzer Task

**Difficulty**: 🟡 Medium  
**Skills**: Data cleaning, date functions, text parsing, statistical analysis, conditional logic  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Analyze messy, real-world data about houseplant propagation attempts to identify which methods and plant types have the highest success rates. Clean up inconsistent formatting, calculate success rates, identify fastest-rooting plants, and determine most reliable techniques.

## Task Description

A plant hobbyist has been tracking propagation attempts for 8 months but recorded data informally:
- Inconsistent date formats ("March 15", "3/15/23", "mid-March", "2023-03-20")
- Various shorthand for methods ("water prop", "soil", "perlite", "LECA")
- Informal outcome descriptions ("roots!", "rotted ☹", "gave up", "success", "dead")

The agent must:
1. Standardize inconsistent date formats
2. Determine success/failure from informal outcome text
3. Calculate rooting duration for successful attempts
4. Calculate success rates by propagation method
5. Calculate success rates by plant type
6. Determine average rooting time for successful propagations
7. Create summary table(s) with insights
8. Apply conditional formatting to highlight patterns

## Expected Results

**Cleaned Data:**
- Standardized dates in helper columns
- Success/failure determination column
- Rooting duration calculated (days between cutting and rooting)

**Analysis:**
- Success rate by method (e.g., "Water: 85%", "Soil: 65%")
- Success rate by plant type (e.g., "Pothos: 90%", "String of Pearls: 45%")
- Average rooting time by method or plant type
- Summary table showing key insights

**Formatting:**
- Conditional formatting highlighting high/low success rates
- Clear visual distinction between successful and failed propagations

## Verification Criteria

1. ✅ **Dates standardized**: Helper column or formula standardizes inconsistent date formats
2. ✅ **Success determination**: Column identifies success/failure based on outcome text
3. ✅ **Duration calculated**: Days between cutting and rooting computed for successful propagations
4. ✅ **Success rate by method**: Summary shows success % for each propagation method (3+ methods)
5. ✅ **Success rate by plant**: Summary shows success % for each plant type (5+ plant types)
6. ✅ **Average rooting time**: Calculation of mean days to root
7. ✅ **Conditional formatting applied**: At least one formatting rule highlighting metrics
8. ✅ **Summary table exists**: Separate section summarizing key insights

**Pass Threshold**: 75% (6/8 criteria must pass)

## Skills Tested

- Date parsing and standardization (DATEVALUE, DATE functions)
- Text manipulation (SEARCH, FIND, LOWER, TRIM)
- Conditional logic (IF, AND, OR)
- Statistical functions (COUNTIF, COUNTIFS, AVERAGEIF, AVERAGE)
- Duration calculations (DAYS, date arithmetic)
- Data grouping and summarization
- Conditional formatting
- Insight generation from messy data

## Tips

- Use DATEVALUE() to convert text dates to proper dates
- Use SEARCH() or FIND() to detect keywords like "root", "rot", "dead" in outcome text
- DAYS() function calculates difference between dates
- COUNTIFS() can count with multiple criteria
- Create summary tables separate from raw data
- Use conditional formatting (Format → Conditional Formatting) to highlight patterns