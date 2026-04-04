# Task: regression_model_comparison

## Overview
Build a multiple linear regression model in JASP to investigate what national-level factors
predict happiness across 155 countries. The agent must configure the regression with the
correct dependent variable, add four covariates, enable diagnostic plots and collinearity
statistics, and save the completed analysis.

## Dataset
World Happiness Report data (`WorldHappiness.csv`, 155 rows):
- **Country** - Country name
- **Happiness Rank** - World happiness ranking
- **Happiness Score** - Composite happiness score (DV)
- **Whisker high** / **Whisker low** - Confidence bounds
- **GDP per Capita** - Economic output (predictor)
- **Family** - Social support (predictor)
- **Life Expectancy** - Healthy life expectancy (predictor)
- **Freedom** - Freedom to make life choices (predictor)
- **Generosity** - Generosity index
- **Government Corruption** - Perceptions of corruption

Source: JASP Data Library (4. Regression / World Happiness.csv)

## What the agent must do
1. Run a Linear Regression with "Happiness Score" as the dependent variable
2. Add covariates: "GDP per Capita", "Family", "Life Expectancy", "Freedom"
3. Enable model fit measures (R-squared, adjusted R-squared), ANOVA test, and coefficient estimates
4. Enable residual diagnostic plots (Q-Q plot of residuals and/or residuals vs. predicted)
5. Enable collinearity diagnostics (VIF)
6. Save the analysis as `/home/ga/Documents/JASP/happiness_regression.jasp`

## Difficulty: Hard
- Multiple configuration panels must be navigated
- Collinearity diagnostics are in a sub-section that requires explicit enabling
- Residual plots require navigating to a plots sub-panel
- Four predictors must each be individually added to the covariates box

## Verification
The verifier parses the saved `.jasp` file (a ZIP archive) and checks:
1. Linear regression analysis present with correct DV
2. All 4 covariates included
3. Residual diagnostic plots enabled
4. Collinearity diagnostics (VIF) enabled
5. File is substantial with computed results
