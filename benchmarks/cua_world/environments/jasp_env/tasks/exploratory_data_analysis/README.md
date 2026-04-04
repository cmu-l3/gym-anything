# Exploratory Data Analysis Task (jasp_env)

## Overview
Comprehensive exploratory data analysis of the Palmer Penguins dataset using multiple JASP modules (Descriptives, Regression/Correlation, ANOVA).

## Dataset
Palmer Penguins morphometric data (334 rows) from JASP's bundled Data Library:
- **Source**: Palmer Station LTER, Antarctica
- **Columns**: species (Adelie/Chinstrap/Gentoo), island, bill_length_mm, bill_depth_mm, flipper_length_mm, body_mass_g, sex, year
- **Path in JASP Data Library**: `Data Library/10. Machine Learning/penguins.csv`

## Task Requirements
The agent must perform a multi-module EDA spanning three JASP analysis types:

1. **Descriptive Statistics** (Descriptives module): Summarize four morphometric variables split by species, with distribution plots
2. **Correlation Analysis** (Regression module): Pearson correlations among four morphometric variables with significance flagging and heatmap
3. **One-Way ANOVA** (ANOVA module): Test species differences in body mass with Tukey post-hoc comparisons

All analyses must be saved into a single `.jasp` file.

## Verification
The verifier parses the saved `.jasp` file (ZIP archive) and inspects `analyses.json` for:
- Presence and configuration of each analysis type
- Correct variable assignments
- Enabled options (split, significance, post-hoc)
- At least 3 distinct analyses
- Substantial file with computed results

## Difficulty: Hard
- Requires navigating three different JASP modules
- Must configure multiple options within each analysis
- Must save all analyses into a single file
