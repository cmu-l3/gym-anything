# Paired Samples Analysis Task

## Overview
This task requires the agent to perform a paired samples t-test and descriptive
statistics analysis using JASP on the Weight Gain dataset. The dataset contains
pre- and post-intervention weight measurements from 16 subjects.

## Dataset
- **File**: `/home/ga/Documents/JASP/WeightGain.csv`
- **Source**: JASP Data Library (`2. T-Tests/Weight Gain.csv`)
- **Size**: 16 observations
- **Variables**:
  - `Weight Before` - weight before intervention (numeric)
  - `Weight After` - weight after intervention (numeric)
  - `Difference` - computed difference (Weight After - Weight Before)

## Task Requirements
The agent must perform two analyses and save the results:

1. **Paired Samples T-Test** (T-Tests module):
   - Compare "Weight Before" vs "Weight After" as paired variables
   - Enable Student's t-test
   - Enable effect size (Cohen's d)
   - Enable descriptive statistics within the t-test options

2. **Descriptive Statistics** (Descriptives module):
   - Compute descriptives for all three variables: Weight Before, Weight After, Difference
   - Include mean, standard deviation, minimum, maximum, and median

3. **Save**: Save the complete analysis as `/home/ga/Documents/JASP/weight_gain_analysis.jasp`

## Difficulty: Hard
The task describes the research goals and desired analyses without prescribing
specific UI navigation steps. The agent must understand how to navigate both
JASP's T-Tests and Descriptives modules and configure multiple analysis options.

## Verification
The verifier unzips the saved .jasp file and parses `analyses.json` to check:
- Paired t-test analysis present with correct variable pairing
- Effect size (Cohen's d) enabled
- Descriptive statistics analysis present with correct variables
- File is substantial with computed results
- Results JSON contains actual computed t-statistic and p-value

## Expected Statistical Results (for reference)
- Paired t-test: significant difference (p < 0.05)
- t-statistic approximately -3.74 (Weight Before vs Weight After)
- Cohen's d approximately -0.94
- Mean Weight Before approximately 81.1, Mean Weight After approximately 82.4
