# Evaluate Diagnostic Test Accuracy (`statcalc_diagnostic_accuracy@1`)

## Overview

This task evaluates the agent's ability to use Epi Info 7's StatCalc **Diagnostic Test** calculator. The agent must interpret a text description of a clinical validation study to derive the 2x2 contingency table (True Positive, False Positive, etc.), compute validity metrics (Sensitivity, Specificity), and analyze how the Positive Predictive Value (PPV) changes when the disease prevalence is adjusted.

## Rationale

**Why this task is valuable:**
- **Clinical Epidemiology Core Skill:** Determining the validity (Sensitivity/Specificity) and utility (PPV/NPV) of diagnostic tools is fundamental to public health and clinical decision-making.
- **Tool Mastery:** Tests a specific StatCalc module distinct from sample size or analysis calculators.
- **Concept Application:** Requires understanding the relationship between prevalence and predictive value, a critical "gotcha" in screening programs.
- **Data Interpretation:** Requires converting a word problem into structured 2x2 data (TP/FP/FN/TN).

**Real-world Context:** A health department is deciding whether to use a new Rapid Antigen Test for mass screening at an airport. The manufacturer claims high accuracy, but the epidemiologist needs to determine the "Positive Predictive Value" in a low-prevalence population (the airport) versus the high-prevalence study population (a hospital).

## Task Description

**Goal:** Use StatCalc's "Diagnostic Test" calculator to evaluate a rapid test based on study data, recalculate predictive values for a low-prevalence setting, and save the results to a structured text file.

**Starting State:**
- Epi Info 7 is running.
- The agent is on the main menu or dashboard.
- No external data file is required (data is provided in the description).

**Scenario Data:**
A validation study for a new **Rapid Fever Test** was conducted on **1,000 patients** presenting to a hospital emergency department.
- **Gold Standard Results:** 200 patients actually had the disease; 800 patients did NOT have the disease.
- **Test Performance (Confirmed Cases):** Among the 200 sick patients, the Rapid Test was positive for **180** of them.
- **Test Performance (Healthy Patients):** Among the 800 healthy patients, the Rapid Test was falsely positive for **40** of them.

**Expected Actions:**
1. Open **StatCalc** from the Epi Info main menu.
2. Navigate to the **Diagnostic Test** (or "Diagnostic Test (2x2)") calculator.
3. Enter the values derived from the scenario into the 2x2 table:
   - **Disease (+) / Test (+):** (True Positives)
   - **Disease (+) / Test (-):** (False Negatives)
   - **Disease (-) / Test (+):** (False Positives)
   - **Disease (-) / Test (-):** (True Negatives)
4. Read the calculated **Sensitivity**, **Specificity**, **Positive Predictive Value (PPV)**, and **Negative Predictive Value (NPV)** (displayed as percentages).
5. Record these baseline values.
6. **Scenario B (Airport Screening):** In the calculator's "Prevalence" field, change the value to **2.0%** (representing a low-risk general population).
7. Read the **New PPV** (Predictive Value Positive) based on this 2% prevalence.
8. Create a results file at `C:\Users\Docker\Documents\diagnostic_report.txt` with the following format (values should be percentages to 1 decimal place, e.g., 95.5%):