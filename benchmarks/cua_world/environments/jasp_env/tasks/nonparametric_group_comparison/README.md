# Nonparametric Group Comparison Task

## Overview
This task requires the agent to perform nonparametric statistical tests and
descriptive visualizations using JASP on the Heart Rate dataset. The dataset
comes from a real study comparing heart rates between runners and controls
across genders (800 observations).

## Dataset
- **File**: `/home/ga/Documents/JASP/HeartRate.csv`
- **Source**: JASP Data Library (`3. ANOVA/Heart Rate.csv`)
- **Size**: 800 observations
- **Variables**:
  - `Gender` - participant gender: Female or Male
  - `Group` - exercise group: Control or Runners
  - `Heart Rate` - resting heart rate (numeric, dependent variable)

## Task Requirements
The agent must configure three distinct analyses:
1. **Kruskal-Wallis test** (nonparametric one-way test) with `Heart Rate` as
   the dependent variable and `Group` as the grouping variable, with
   descriptive statistics enabled
2. **Mann-Whitney U test** (independent samples nonparametric) comparing
   `Heart Rate` between `Gender` groups (Female vs Male), with descriptive
   statistics and effect size enabled
3. **Descriptive Statistics** for `Heart Rate` split by `Group`, including
   boxplots and distribution plots
4. Save the completed analysis as
   `/home/ga/Documents/JASP/heart_rate_nonparametric.jasp`

## Difficulty: Hard
The task requires navigating JASP's less commonly used nonparametric testing
modules rather than the standard parametric tests. The agent must find and
configure the Kruskal-Wallis and Mann-Whitney tests, which are nested within
the T-Tests and ANOVA menus under nonparametric options. The task description
presents the research scenario without prescribing specific UI navigation steps.

## Verification
The verifier unzips the saved .jasp file and parses `analyses.json` to check:
- Kruskal-Wallis analysis present with correct DV and grouping variable
- Mann-Whitney U analysis present with correct DV and grouping variable
- Descriptive statistics present with Heart Rate split by Group and plots
- At least 3 distinct analyses configured
- File is substantial with computed results

## Expected Statistical Results (for reference)
- Kruskal-Wallis: significant difference between Control and Runners groups
- Mann-Whitney U: possible difference between Female and Male heart rates
- Descriptive plots should show distribution differences between groups
