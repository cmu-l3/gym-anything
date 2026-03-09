# Insect Sprays Non-Parametric Analysis Task

## Overview
This task requires the agent to perform non-parametric statistical analysis
using jamovi on the InsectSprays dataset. The dataset comes from a classic
agricultural experiment comparing the effectiveness of six insect sprays
(Beall, 1942). Since insect count data is inherently non-normal (overdispersed,
zero-bounded), the Kruskal-Wallis test is more appropriate than one-way ANOVA.

## Dataset
- **File**: `/home/ga/Documents/Jamovi/InsectSprays.csv`
- **Source**: R built-in dataset via Rdatasets (vincentarelbundock/Rdatasets)
- **Size**: 72 observations (12 per spray type)
- **Variables**:
  - `rownames` - row index from Rdatasets (should be ignored)
  - `count` - number of insects surviving after spraying (integer, dependent variable)
  - `spray` - type of insect spray: A, B, C, D, E, or F (6 levels)

## Task Requirements
The agent must recognize that count data violates normality assumptions and
apply non-parametric methods:
1. **Descriptive statistics** for `count` split by `spray` to examine group
   distributions (means, medians, SDs across the six spray types)
2. **Shapiro-Wilk normality test** on the `count` variable to formally assess
   the normality assumption
3. **Kruskal-Wallis test** (non-parametric alternative to one-way ANOVA)
   comparing `count` across the six `spray` groups
4. **Pairwise comparisons** (DSCF / Dwass-Steel-Critchlow-Fligner, or Dunn)
   to identify which specific spray pairs differ significantly
5. Save the completed analysis as
   `/home/ga/Documents/Jamovi/InsectSprayAnalysis.omv`

## Difficulty: Hard
The task describes the research question and desired analyses in statistical
terms without prescribing specific UI navigation steps. The agent must:
- Recognize that count data is non-normal and non-parametric tests are needed
- Find the Kruskal-Wallis test in jamovi's menus (under ANOVA > Non-Parametric
  > One-Way ANOVA (Kruskal-Wallis))
- Enable pairwise comparisons (DSCF) within the Kruskal-Wallis options
- Conduct a Shapiro-Wilk normality test (under Exploration > Descriptives >
  Statistics > Shapiro-Wilk, or T-Tests > Independent Samples T-Test >
  Assumption Checks)
- Save the file in .omv format

## Verification
The verifier uses a two-stage approach:

1. **export_result.sh** (post_task hook): Extracts the .omv file (ZIP archive),
   parses the internal `index.html` for analysis keywords, and writes a
   structured JSON to `/tmp/insect_nonparametric_result.json`.

2. **verifier.py**: Multi-criterion scoring (100 points total):
   - File saved at the correct path (15 pts)
   - Valid .omv structure (ZIP with expected contents) (10 pts)
   - Descriptives present with count split by spray (20 pts)
   - Normality test (Shapiro-Wilk) present (15 pts)
   - Kruskal-Wallis test present with correct variables (25 pts)
   - Pairwise comparisons present (15 pts)

   Pass threshold: 70 points

## Expected Statistical Results (for reference)
- Sprays C, D, and E have much lower insect counts than A, B, and F
- Shapiro-Wilk test: count data significantly departs from normality
  (W ~ 0.89, p < 0.001)
- Kruskal-Wallis: highly significant difference among spray groups
  (chi-squared ~ 54.7, df = 5, p < 0.001)
- Pairwise comparisons: sprays C, D, E differ significantly from A, B, F;
  within-cluster differences are typically non-significant

## jamovi .omv File Format
The .omv format is a ZIP archive containing:
- `index.html` - rendered analysis output (HTML tables and text)
- `meta` - metadata about the file
- `data.bin` / `strings.bin` - binary data storage
- `xdata.json` - column metadata
- Various analysis result files

The verifier parses `index.html` for the presence of analysis keywords
rather than structured JSON options (unlike JASP's analyses.json approach).
