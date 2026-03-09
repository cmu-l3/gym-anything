# Coffee Roast Freshness Tracker Task

**Difficulty**: 🟡 Medium  
**Skills**: Date formulas, conditional formatting, data sorting, time-sensitive calculations  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Help a home coffee roaster organize their roast log to identify which beans are in the optimal brewing window. Calculate days since roasting, apply visual formatting to highlight freshness categories, and sort data to prioritize which beans to brew this week.

## Task Description

The agent must:
1. Open a coffee roast log spreadsheet with roast dates spanning several weeks
2. Add a "Days Since Roast" column with formula `=TODAY()-C2` (where C2 is roast date)
3. Copy the formula down to all data rows
4. Apply conditional formatting to the Days column to highlight freshness:
   - **0-4 days**: Light yellow/cream (too fresh)
   - **5-14 days**: Green (peak brewing window)
   - **15-21 days**: Orange (still good)
   - **22+ days**: Red (stale)
5. Sort data by Roast Date (ascending or descending)
6. Save the file

## Coffee Freshness Context

Freshly roasted coffee needs to "degas" for several days before brewing. The optimal brewing window is typically:
- **0-4 days**: Too fresh (excess CO2, inconsistent extraction)
- **5-14 days**: Peak flavor window
- **15-21 days**: Still good but flavor declining
- **22+ days**: Stale (flavor degradation accelerates)

## Expected Results

- **Column F**: "Days Since Roast" header with formula `=TODAY()-C2` copied down
- **Conditional Formatting**: Applied to Days column (F2:F13 or similar)
- **Sorted Data**: Rows sorted by Roast Date in chronological order
- **Visual Clarity**: Color-coded cells showing freshness at a glance

## Verification Criteria

1. ✅ **Formula Present**: Days-since-roast formula exists using TODAY() or NOW()
2. ✅ **Conditional Formatting Applied**: At least 2 formatting rules detected
3. ✅ **Data Sorted**: Roast dates in chronological order (ascending or descending)
4. ✅ **Calculations Correct**: Days values match expected calculations (±1 day tolerance)

**Pass Threshold**: 75% (3/4 criteria must pass)

## Skills Tested

- Date arithmetic and TODAY() function
- Formula copying across multiple rows
- Conditional formatting with multiple rules
- Data sorting while maintaining row integrity
- Time-sensitive inventory management
- Visual data organization

## Sample Data

| Bean Name | Origin | Roast Date | Weight (g) | Roast Level |
|-----------|--------|------------|------------|-------------|
| Ethiopia Yirgacheffe | Ethiopia | 2024-01-15 | 250 | Light |
| Colombia Huila | Colombia | 2024-01-22 | 300 | Medium |
| Kenya AA | Kenya | 2024-01-18 | 250 | Medium-Light |

## Tips

- Use `=TODAY()-C2` where C2 contains the roast date
- Select the Days column range before applying conditional formatting
- Create multiple formatting rules for different day ranges
- Use Format → Conditional Formatting → Condition...
- Sort entire data range (including headers) via Data → Sort
- The formula will automatically update daily as TODAY() changes