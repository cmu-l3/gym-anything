# Exam Multi-Analysis Task (jamovi_env)

## Overview
Comprehensive multi-analysis investigation of exam performance using the ExamAnxiety.csv dataset in jamovi. The agent must run three distinct statistical analyses (descriptive statistics, independent samples t-test, and correlation matrix) and save the completed project as a single .omv file.

## Dataset
**ExamAnxiety.csv** (Field, 2013) -- 103 university students from an exam performance study.

| Column   | Description                            | Type       |
|----------|----------------------------------------|------------|
| Code     | Participant identifier                 | Integer    |
| Revise   | Hours spent revising                   | Continuous |
| Exam     | Exam score (percentage)                | Continuous |
| Anxiety  | Exam anxiety score (standardized scale)| Continuous |
| Gender   | Male / Female                          | Nominal    |

**Source**: JASP Data Library (Field, 2013, "Discovering Statistics Using R"), downloaded during `install_jamovi.sh`.
**Path in VM**: `/home/ga/Documents/Jamovi/ExamAnxiety.csv`

## Task Requirements
The agent must perform three analyses in jamovi:

### 1. Descriptive Statistics (Exploration > Descriptives)
- Variables: Exam, Revise, Anxiety
- Split by: Gender
- Statistics: Mean, Median, Standard Deviation, Minimum, Maximum

### 2. Independent Samples T-Test (T-Tests > Independent Samples T-Test)
- Dependent variable: Exam
- Grouping variable: Gender
- Hypothesis: two-tailed (Group 1 != Group 2)

### 3. Correlation Matrix (Regression > Correlation Matrix)
- Variables: Exam, Revise, Anxiety
- Correlation type: Pearson (default)

### Save
- Save the file as: `/home/ga/Documents/Jamovi/ExamAnalysis.omv`

## Ground Truth (Expected Results)
Based on the ExamAnxiety.csv dataset (N=103):

### Descriptive Statistics
- **Exam**: Mean ~ 56.6, SD ~ 25.7 (varies by gender)
- **Revise**: Mean ~ 19.9, SD ~ 14.3
- **Anxiety**: Mean ~ 65.6, SD ~ 18.6
- Gender split should show separate summaries for Male and Female

### Independent Samples T-Test
- Tests whether Exam scores differ significantly between Male and Female
- Expected: moderate effect, may or may not reach significance at p < .05

### Correlation Matrix
- Exam--Revise: positive correlation (more revision -> higher exam score)
- Exam--Anxiety: negative correlation (more anxiety -> lower exam score)
- Revise--Anxiety: negative correlation (more revision -> less anxiety)

## Verification Strategy
The verifier parses the saved `.omv` file (ZIP archive containing `index.html` with rendered analysis output) and checks for:

1. **File existence** (15 pts): .omv file exists at the expected path
2. **Valid .omv structure** (10 pts): File is a valid ZIP with expected contents
3. **Descriptives analysis** (25 pts): Descriptives present with Exam/Revise/Anxiety split by Gender
4. **T-test analysis** (25 pts): Independent Samples T-Test with Exam as DV and Gender as grouping variable
5. **Correlation matrix** (25 pts): Correlation Matrix with Exam, Revise, Anxiety

**Pass threshold**: 70/100 (need at least the core analyses)

## Difficulty: Hard
- Description says WHAT to do but NOT which menus/buttons to click
- Requires navigating three different jamovi analysis modules
- Must configure multiple options within each analysis
- Must save all analyses into a single .omv file
- Agent must discover the correct menu paths independently
