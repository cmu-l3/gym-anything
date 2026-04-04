# Judge Score Normalization Task

**Difficulty**: 🟡 Medium  
**Skills**: Statistical analysis, z-score normalization, formula creation, ranking  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Normalize biased judge scores from a pie competition to create fair rankings. This task tests statistical reasoning, advanced formula creation, and understanding of data normalization concepts essential for fair evaluation systems.

## Task Description

A county fair pie competition has 8 pies rated by 4 judges on a 1-10 scale. However, the judges have dramatically different scoring styles:
- **Judge 2** is notoriously harsh (scores in 4-6 range)
- **Judge 4** is extremely generous (scores in 9-10 range)
- **Judges 1 & 3** are moderate

Simply averaging raw scores would unfairly advantage pies evaluated by the generous judge. The agent must:

1. Recognize the judge bias problem from the data
2. Calculate judge statistics (mean and standard deviation)
3. Apply z-score normalization: `z = (score - judge_mean) / judge_stdev`
4. Calculate average normalized scores for each pie
5. Rank pies by normalized scores
6. Identify the top 3 winners

## Starting Data

8 pies × 4 judges = 32 scores in CSV format:
- Columns: Pie Name, Judge 1, Judge 2, Judge 3, Judge 4
- Judge 2's scores consistently 2-3 points lower
- Judge 4's scores consistently 1-2 points higher

## Expected Results

- **Normalized Scores**: Z-scores for all 32 judge-pie combinations
- **Judge Statistics**: Mean ~0, Std Dev ~1 after normalization
- **Final Rankings**: Fair rankings based on average z-scores
- **Top 3 Winners**: Clearly identified with conditional formatting (optional)

## Verification Criteria

1. ✅ **Z-scores calculated correctly**: Proper standardization formulas applied
2. ✅ **Rankings based on normalized scores**: Final ranks use z-scores, not raw scores
3. ✅ **All data processed**: All 8 pies × 4 judges normalized
4. ✅ **Rankings differ from naive approach**: Normalization changed results
5. ✅ **Top 3 identified**: Clear winners determined

**Pass Threshold**: 75% (4/5 criteria must pass)

## Skills Tested

- Statistical literacy (recognizing bias, understanding normalization)
- Advanced formula creation (AVERAGE, STDEV, z-score calculation)
- Absolute vs. relative cell references
- Multi-sheet organization (optional)
- RANK function usage
- Conditional formatting (optional)
- Data integrity and quality assurance

## Key Concepts

**Z-Score Normalization**: Transforms scores to "standard deviations from mean"
- Formula: `z = (x - μ) / σ`
- Result: All judges normalized to mean=0, std=1
- Enables fair comparison across different scoring scales

**Why Simple Averaging Fails**: 
- Pie rated [6,5,6,9] average = 6.5
- Pie rated [7,6,7,10] average = 7.5
- But Judge 2 gives 5-6 to excellent pies, Judge 4 gives 9-10 to everything
- Normalization reveals true quality relative to each judge's standards

## Setup

The setup script:
- Creates CSV with 8 pie scores showing clear judge bias
- Launches LibreOffice Calc with the data file
- Positions window and focuses for agent interaction

## Export

The export script:
- Saves the workbook as ODS format
- Preserves all sheets (raw data, calculations, rankings)
- Closes LibreOffice Calc

## Verification

Verifier performs sophisticated checks:
1. **Mathematical validation**: Z-score formulas are correct
2. **Statistical properties**: Normalized scores have mean≈0, std≈1 per judge
3. **Ranking logic**: Final ranks ordered by average z-scores
4. **Formula inspection**: Confirms formulas (not hardcoded values)
5. **Impact assessment**: Rankings differ from naive averaging (proves normalization worked)

## Tips for Agents

- Start by examining the data - notice Judge 2's scores are all low, Judge 4's all high
- Calculate each judge's mean and standard deviation first
- Apply z-score formula to each cell: `=(raw_score - judge_mean) / judge_stdev`
- Use $ for absolute references when copying formulas
- Average the 4 z-scores for each pie
- Use RANK function on average z-scores for final rankings
- Compare to what naive averaging would give to verify improvement

## Real-World Applications

- Academic grading with multiple TAs
- Olympic judging (figure skating, gymnastics)
- Hiring panels with different interviewer standards
- Grant review processes
- Wine/food competitions
- Performance reviews across departments