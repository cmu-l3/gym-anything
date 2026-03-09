# Tooth Growth Factorial ANOVA Task

## Overview
This task requires the agent to perform a two-way (factorial) ANOVA analysis
using jamovi on the ToothGrowth dataset. The dataset comes from a classic study
on the effect of vitamin C on tooth growth in guinea pigs (Crampton, 1947).

## Dataset
- **File**: `/home/ga/Documents/Jamovi/ToothGrowth.csv`
- **Source**: R built-in dataset via Rdatasets (vincentarelbundock/Rdatasets)
- **Size**: 60 observations
- **Variables**:
  - `rownames` - row index from Rdatasets (should be ignored)
  - `len` - tooth length in mm (numeric, dependent variable)
  - `supp` - supplement type: OJ (orange juice) or VC (ascorbic acid)
  - `dose` - vitamin C dose in mg/day: 0.5, 1, or 2

## Task Requirements
The agent must configure a complete factorial ANOVA analysis:
1. Run a two-way ANOVA with `len` as the dependent variable
2. Set `supp` and `dose` as fixed factors (with interaction term supp x dose)
3. Enable assumption checks: homogeneity of variances (Levene's test) and
   normality of residuals (Shapiro-Wilk test)
4. Enable post-hoc comparisons (Tukey) for the main effects
5. Include a descriptives table showing means and standard deviations per cell
6. Save the completed analysis as `/home/ga/Documents/Jamovi/ToothGrowthAnalysis.omv`

## Difficulty: Hard
The task describes the research question and desired analyses in statistical
terms without prescribing specific UI navigation steps. The agent must understand
how to navigate jamovi's ANOVA module, configure multiple analysis sub-options
(assumption checks, post-hoc tests, descriptives), and save the file in .omv
format. The interaction term and assumption checks add complexity beyond a
simple one-way ANOVA.

## Verification
The verifier uses a two-stage approach:

1. **export_result.sh** (post_task hook): Extracts the .omv file (ZIP archive),
   parses the internal `index.html` for analysis keywords, and writes a
   structured JSON to `/tmp/tooth_growth_factorial_result.json`.

2. **verifier.py**: Multi-criterion scoring (100 points total):
   - File saved at the correct path (15 pts)
   - Valid .omv structure (ZIP with expected contents) (10 pts)
   - ANOVA analysis present with correct DV and factors (25 pts)
   - Interaction term (supp x dose) included (15 pts)
   - Assumption checks: homogeneity + normality tests (15 pts)
   - Post-hoc comparisons present (10 pts)
   - Descriptives table present (10 pts)

   Pass threshold: 70 points

## Expected Statistical Results (for reference)
- Significant main effect of `dose` (F ~ 92, p < 0.001)
- Significant main effect of `supp` (F ~ 15, p < 0.001)
- Significant interaction effect supp x dose (F ~ 4.1, p ~ 0.02)
- Post-hoc: dose levels 0.5 vs 1 and 0.5 vs 2 significantly different
- OJ generally produces longer teeth than VC at lower doses, but the
  difference disappears at the 2 mg/day dose (interaction effect)

## jamovi .omv File Format
The .omv format is a ZIP archive containing:
- `index.html` - rendered analysis output (HTML tables and text)
- `meta` - metadata about the file
- `data.bin` / `strings.bin` - binary data storage
- `xdata.json` - column metadata
- Various analysis result files

The verifier parses `index.html` for the presence of analysis keywords
rather than structured JSON options (unlike JASP's analyses.json approach).
