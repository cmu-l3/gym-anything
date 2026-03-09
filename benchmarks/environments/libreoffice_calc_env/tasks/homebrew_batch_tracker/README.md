# Homebrew Beer Batch Tracker Task

**Difficulty**: 🟡 Medium  
**Skills**: Formula creation, scientific calculation, conditional formatting, data organization  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Organize homebrewing fermentation data, calculate alcohol by volume (ABV) from gravity readings, and use conditional formatting to identify successful batches within target range. This task tests formula implementation, mathematical calculation with domain-specific knowledge, and analytical formatting skills.

## Task Description

The agent must:
1. Review the provided spreadsheet with 6 homebrew batches containing Original Gravity (OG) and Final Gravity (FG) data
2. Understand the ABV calculation formula: ABV (%) = (OG - FG) × 131.25
3. Create formulas in the ABV column to calculate alcohol content for each batch
4. Copy the formula to all batches with complete fermentation data
5. Apply conditional formatting to highlight batches within the target ABV range (4.5-6.5%)
6. Save the completed spreadsheet

## Initial Data Structure

| Batch Name | Brew Date | Original Gravity | Final Gravity | Target ABV | ABV | Quality Notes |
|------------|-----------|------------------|---------------|------------|-----|---------------|
| Pale Ale #1 | 2024-01-15 | 1.055 | 1.012 | 4.5-6.5% | (empty) | Slightly sweet finish |
| Belgian Wit | 2024-02-03 | 1.048 | 1.010 | 4.5-6.5% | (empty) | Excellent clarity |
| IPA Experiment | 2024-02-28 | 1.062 | 1.014 | 4.5-6.5% | (empty) | Good hop character |
| Light Summer Ale | 2024-03-10 | 1.045 | 1.008 | 4.5-6.5% | (empty) | Very dry, crisp |
| Amber Ale | 2024-03-22 | 1.058 | 1.015 | 4.5-6.5% | (empty) | Balanced malt profile |
| Stout Attempt | 2024-04-05 | 1.070 | (missing) | 4.5-6.5% | (empty) | Still fermenting |

## Expected Results

- **ABV formulas** in column F for all batches with complete OG/FG data
- **Calculated ABV values**:
  - Pale Ale #1: 5.64%
  - Belgian Wit: 4.99%
  - IPA Experiment: 6.30%
  - Light Summer Ale: 4.86%
  - Amber Ale: 5.64%
  - Stout Attempt: (blank or error - missing FG)
- **Conditional formatting** highlighting cells with ABV between 4.5% and 6.5% (green or similar positive indicator)

## Verification Criteria

1. ✅ **ABV Formulas Present**: All batches with OG/FG data have proper formulas (pattern: `=(C-D)*131.25`)
2. ✅ **Calculations Correct**: Computed ABV values match expected results (within 0.1% tolerance)
3. ✅ **Conditional Formatting Applied**: Formatting rule highlights target range (4.5-6.5%)
4. ✅ **Data Integrity**: Original brewing data preserved without corruption

**Pass Threshold**: 75% (3/4 criteria must pass)

## Skills Tested

- Formula syntax and cell references
- Mathematical calculation with scientific constants
- Formula propagation across rows
- Conditional formatting rule creation
- Understanding domain-specific calculations
- Data quality assessment (handling missing values)

## Domain Knowledge

**What is ABV?**
- Alcohol By Volume - percentage of alcohol in the finished beer
- Calculated from the difference between starting sugar (OG) and residual sugar (FG)
- Formula: ABV = (OG - FG) × 131.25

**Typical ABV Ranges:**
- Light beers: 3-4%
- Standard ales: 4-6%
- Strong ales: 6-8%
- Imperial/barleywine: 8-12%

**Target Range (4.5-6.5%):**
- This represents typical sessionable to moderate strength ales
- Batches outside this range are either too weak or too strong for the intended style

## Tips

- Gravity readings are typically 1.030 to 1.090 (1 = water density)
- The constant 131.25 is derived from the density difference of alcohol vs water
- Conditional formatting: Format → Conditional Formatting → Condition
- Use "between" condition type for the 4.5-6.5% range
- Batches with missing FG data should show formula errors or blank (acceptable)