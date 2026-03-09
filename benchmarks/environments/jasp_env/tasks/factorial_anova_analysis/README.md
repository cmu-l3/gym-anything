# Factorial ANOVA Analysis Task

## Overview
This task requires the agent to perform a two-way (factorial) ANOVA analysis
using JASP on the Tooth Growth dataset. The dataset comes from a real study on
the effect of vitamin C on tooth growth in guinea pigs (Crampton 1947).

## Dataset
- **File**: `/home/ga/Documents/JASP/ToothGrowth.csv`
- **Source**: JASP Data Library (`3. ANOVA/Tooth Growth.csv`)
- **Size**: 60 observations
- **Variables**:
  - `len` - tooth length (numeric, dependent variable)
  - `supp` - supplement type: OJ (orange juice) or VC (ascorbic acid)
  - `dose` - dose in milligrams/day: 500, 1000, or 2000

## Task Requirements
The agent must configure a complete factorial ANOVA analysis:
1. Run a two-way ANOVA with `len` as dependent variable
2. Set `supp` and `dose` as fixed factors (interaction included)
3. Enable post-hoc comparisons for the `dose` factor
4. Enable descriptive statistics
5. Enable descriptive plots (interaction plot: supp x dose)
6. Enable eta-squared effect size
7. Save as `/home/ga/Documents/JASP/tooth_growth_anova.jasp`

## Difficulty: Hard
The task describes the research question and desired analyses without
prescribing specific UI navigation steps. The agent must understand how
to navigate JASP's ANOVA module and configure multiple analysis options.

## Verification
The verifier unzips the saved .jasp file and parses `analyses.json` to check:
- ANOVA analysis present with correct DV and factors
- Post-hoc comparisons enabled for dose
- Descriptive statistics enabled
- Descriptive/interaction plots enabled
- File is substantial with computed results

## Expected Statistical Results (for reference)
- Significant main effects for both `supp` and `dose`
- Significant interaction effect (supp x dose)
- F-statistic for `dose` is large (~92)
- F-statistic for `supp` is moderate (~15)
