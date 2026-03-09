# Titanic Survival Chi-Square Analysis Task (jamovi_env)

## Overview
Categorical analysis of Titanic survival patterns using chi-square tests of
independence in jamovi. The agent must run two separate contingency table
analyses and configure expected counts and percentages, then save the completed
project as an .omv file.

## Dataset
**TitanicSurvival.csv** -- approximately 1,309 passengers from the RMS Titanic.

| Column         | Description                        | Type     |
|----------------|------------------------------------|----------|
| rownames       | Passenger name (text)              | Nominal  |
| survived       | Survival status: yes / no          | Nominal  |
| sex            | Passenger sex: female / male       | Nominal  |
| age            | Age in years (some NA values)      | Continuous |
| passengerClass | Ticket class: 1st / 2nd / 3rd      | Ordinal  |

**Source**: Rdatasets (vincentarelbundock/Rdatasets), TitanicSurvival from the
`carData` R package.
**Path in VM**: `/home/ga/Documents/Jamovi/TitanicSurvival.csv`

## Task Requirements
The agent must perform two chi-square tests of independence using jamovi's
Frequencies module (Frequencies > Independent Samples -- Chi-square test of
association, also called "Contingency Tables"):

### 1. Chi-Square: survived x passengerClass
- Rows: `survived`
- Columns: `passengerClass`
- Enable expected counts in the cells
- Enable row percentages (and/or column percentages)

### 2. Chi-Square: survived x sex
- Rows: `survived`
- Columns: `sex`
- Enable expected counts in the cells
- Enable row percentages (and/or column percentages)

### Save
- Save the file as: `/home/ga/Documents/Jamovi/TitanicAnalysis.omv`

## Ground Truth (Expected Results)
Based on the TitanicSurvival.csv dataset (N ~ 1309):

### Chi-Square: survived x passengerClass
- Survival rates differ significantly by class
- 1st class: ~62% survived; 2nd class: ~41% survived; 3rd class: ~25% survived
- Chi-square highly significant (p < 0.001)

### Chi-Square: survived x sex
- Survival rates differ significantly by sex
- Female: ~73% survived; Male: ~21% survived
- Chi-square highly significant (p < 0.001)

## Verification Strategy
The verifier uses a two-stage approach:

1. **export_result.sh** (post_task hook): Extracts the .omv file (ZIP archive),
   parses the internal `index.html` for analysis keywords, and writes a
   structured JSON to `/tmp/titanic_survival_result.json`.

2. **verifier.py**: Multi-criterion scoring (100 points total):
   - File saved at the correct path (15 pts)
   - Valid .omv structure (ZIP with expected contents) (10 pts)
   - Chi-square for survived x passengerClass present (25 pts)
   - Chi-square for survived x sex present (25 pts)
   - Expected counts enabled in at least one analysis (10 pts)
   - Percentages enabled in at least one analysis (15 pts)

   Pass threshold: 70 points

## Difficulty: Hard
- Description says WHAT to do but NOT which menus/buttons to click
- Requires finding the Frequencies module and Contingency Tables analysis
- Must configure two separate chi-square analyses with correct variable assignments
- Must enable additional cell statistics (expected counts, percentages)
- Must save the completed analyses into a single .omv file
- Agent must discover the correct menu paths independently

## jamovi .omv File Format
The .omv format is a ZIP archive containing:
- `index.html` - rendered analysis output (HTML tables and text)
- `meta` - metadata about the file
- `data.bin` / `strings.bin` - binary data storage
- `xdata.json` - column metadata
- Various analysis result files

The verifier parses `index.html` for the presence of analysis keywords
rather than structured JSON options (unlike JASP's analyses.json approach).
