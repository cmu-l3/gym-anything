# Aggregate Attack Rate Data (`aggregate_attack_rates@1`)

## Overview
This task requires the agent to use Epi Info 7's Classic Analysis module to transform and aggregate outbreak data. The agent must recode a continuous variable (Age) into categorical groups, perform a stratified aggregation to obtain case counts by group and illness status, and export the resulting summary table to a CSV file.

## Rationale
**Why this task is valuable:**
- **Data Transformation**: Tests the ability to use the `RECODE` command to turn continuous data into categorical variables (a ubiquitous task in epidemiology).
- **Data Aggregation**: Verifies proficiency with the `SUMMARIZE` or `FREQ` commands to generate aggregate statistics (counts) from individual line-list data.
- **Workflow Management**: Requires reading data, processing it, creating an intermediate table, and exporting the result to a portable format.
- **Real-world Relevance**: Epidemiologists frequently need to collapse individual patient records into summary tables (e.g., "Cases by Age Group") for reporting or external visualization.

**Real-world Context:** You are an epidemiologist investigating the Oswego outbreak. The public health director has requested a summary table showing the number of ill and well persons stratified by age group to calculate age-specific attack rates in Excel. You need to process the raw line list and generate this summary file.

## Task Description

**Goal:** Load the Oswego dataset, recode the `Age` variable into four distinct age groups, aggregate the data to count the number of individuals by Age Group and Illness status, and export the summary to `C:\Users\Docker\Documents\AgeIllnessSummary.csv`.

**Starting State:**
- Epi Info 7 is installed.
- The agent is at the Epi Info 7 main menu or desktop.
- The standard sample project `Sample.prj` (containing the `Oswego` dataset) is available in the default location.

**Expected Actions:**
1. Open the **Classic Analysis** module.
2. **Read** the `Oswego` table from the `Sample.prj` project.
3. **Recode** the `Age` variable into a new variable named `AgeGroup` using the following cutoffs:
   - 0 to 19 ➔ "0-19"
   - 20 to 39 ➔ "20-39"
   - 40 to 59 ➔ "40-59"
   - 60 to 99 ➔ "60+"
4. **Summarize** the data to create a count of records grouped by `AgeGroup` and `Ill` (Illness Status).
5. **Export** the resulting summary data to a CSV file named `AgeIllnessSummary.csv` located in `C:\Users\Docker\Documents\`.

**Final State:**
- A file `C:\Users\Docker\Documents\AgeIllnessSummary.csv` exists.
- The file contains columns representing `AgeGroup`, `Ill` (status), and the `Count` (frequency) of records.

## Verification Strategy

### Primary Verification: Output File Analysis
The verification script parses the output CSV to ensure correct data transformation and aggregation.

1. **File Existence**: Checks if `C:\Users\Docker\Documents\AgeIllnessSummary.csv` exists.
2. **Structure Check**: Verifies headers include `AgeGroup`, `Ill`, and a Count column.
3. **Content Verification**:
   - Reads the CSV into a dataframe.
   - Checks that `AgeGroup` contains the expected labels ("0-19", "20-39", etc.).
   - Sums the counts to verify total records (should match Oswego N=75).

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| **File Creation** | 20 | The CSV file exists at the specified path. |
| **Columns Present** | 20 | File contains `AgeGroup`, `Ill`, and a count column. |
| **Recoding Logic** | 30 | `AgeGroup` column contains correct categories (0-19, 20-39, etc.). |
| **Aggregation Accuracy** | 30 | The counts for specific groups match the ground truth. |
| **Total** | **100** | |

Pass Threshold: 80 points.