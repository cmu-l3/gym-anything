# Community Chili Cook-Off Score Normalizer Task

**Difficulty**: 🟡 Medium  
**Skills**: Data normalization, missing data handling, ranking, formula construction  
**Duration**: 180 seconds  
**Steps**: ~20

## Objective

Handle realistic scoring data from a community cooking competition where judges used inconsistent rating scales. Normalize scores across different scales (1-5 vs 1-10), handle missing data appropriately, calculate final rankings, and determine prize amounts from a fixed prize pool.

## Task Description

A local community center runs an annual chili cook-off competition with 8 contestants and 4 judges. The organizer received judge scoring sheets but discovered that:
- Judges 1 and 2 used a 1-10 scale
- Judges 3 and 4 used a 1-5 scale  
- Some judges didn't score all entries (missing data)

The agent must:
1. Open the spreadsheet with raw judge scores
2. Create normalized score columns (convert all to 1-10 scale)
3. Handle missing data (exclude from averages, don't count as zero)
4. Calculate average normalized score per contestant
5. Rank contestants by average score
6. Determine prize amounts (1st=$250, 2nd=$150, 3rd=$100 from $500 pool)
7. Save the completed spreadsheet

## Expected Results

### Normalized Scores
- Judges 1-2 (1-10 scale): Copy scores directly
- Judges 3-4 (1-5 scale): Multiply by 2 to convert to 1-10 scale
- Missing scores: Keep blank (do NOT substitute with zero)

### Average Score Column
- Calculate average only from available judge scores
- Use AVERAGE function (automatically handles blanks) or SUMIF/COUNTIF
- Missing scores should NOT reduce average

### Ranking Column
- Use RANK function with descending order
- Highest average score = Rank 1
- Second highest = Rank 2, etc.

### Prize Amount Column
- Rank 1: $250 (50% of $500)
- Rank 2: $150 (30% of $500)
- Rank 3: $100 (20% of $500)
- Ranks 4-8: $0

## Verification Criteria

1. ✅ **Normalization Correct**: All 1-5 scores converted to 1-10 scale (×2)
2. ✅ **Missing Data Handled**: Averages calculated only from available scores
3. ✅ **Rankings Accurate**: Contestants ranked 1-8 by average (highest to lowest)
4. ✅ **Prizes Correct**: $250/$150/$100 for ranks 1/2/3, $0 for others
5. ✅ **Formulas Used**: Calculations use formulas, not manual entry
6. ✅ **No Errors**: No #DIV/0!, #VALUE!, or #REF! errors

**Pass Threshold**: 70% (4/6 criteria must pass)

## Skills Tested

- Scale normalization and mathematical transformation
- Missing data handling strategies
- Statistical functions (AVERAGE, COUNT, COUNTIF)
- Logical functions (IF, ISBLANK, RANK)
- Proportional calculations
- Fair data processing
- Formula debugging

## Sample Data Structure

**Raw Scores (Input):**