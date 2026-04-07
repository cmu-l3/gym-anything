# Go/No-Go Inhibitory Control Analysis (`gng_inhibitory_control_analysis@1`)

## Overview
This task evaluates the agent's ability to process trial-by-trial data from a classic Go/No-Go (GNG) cognitive task, compute behavioral indices of inhibitory control (omission and commission errors), and apply Signal Detection Theory (SDT) to calculate d-prime (d'). The agent must also screen the data for physiologically impossible responding patterns indicative of a hardware error or non-compliant participant.

## Rationale
**Why this task is valuable:**
- Tests the application of Signal Detection Theory (d', hit rates, false alarm rates) to behavioral data.
- Requires correctly implementing standard edge-case corrections for perfect performance (0 or 100% rates) to avoid infinite d' values.
- Evaluates data quality control by applying theoretically grounded exclusion criteria (differentiating a fast responder from a stuck key).
- Focuses on clinical performance metrics (errors of omission vs. commission) rather than just reaction times.

**Real-world Context:** A postsecondary psychology teacher has collected Go/No-Go data from 25 students for an undergraduate cognitive psychology lab demonstration. Before presenting the data to the class to illustrate the principles of response inhibition and SDT, the instructor needs an automated script to compute the metrics, aggregate the group data, and identify a known corrupted file where a student placed a book on the spacebar, resulting in 100% responses.

## Task Description

**Goal:** Compute omission errors, commission errors, mean Hit RT, and d-prime for each valid participant in a Go/No-Go dataset, exclude the non-compliant participant, and produce a JSON report at `~/pebl/analysis/gng_report.json`.

**Starting State:** A text editor is open displaying the task instructions. The raw trial-by-trial dataset is located at `~/pebl/data/gng_data.csv`. The `~/pebl/analysis/` directory exists but is empty.

**Data Format:**
`gng_data.csv` columns:
- `participant_id`: participant ID (e.g., sub-01 through sub-25, plus sub-99)
- `trial`: trial number
- `condition`: `GO` (participant should respond) or `NOGO` (participant should withhold response)
- `response`: `1` if the participant pressed the spacebar, `0` if they made no response
- `rt_ms`: reaction time in milliseconds (0 if no response was made)

**Analysis Definitions & Rules:**
For each participant, calculate:
1. **Omission Errors**: Count of `GO` trials where `response == 0` (Misses).
2. **Commission Errors**: Count of `NOGO` trials where `response == 1` (False Alarms).
3. **Hit Rate**: (Count of `GO` trials with `response == 1`) / (Total `GO` trials).
4. **False Alarm Rate**: (Count of `NOGO` trials with `response == 1`) / (Total `NOGO` trials).
5. **Mean Hit RT**: Mean `rt_ms` for `GO` trials where `response == 1`.
6. **d-prime (d')**: `Z(Hit Rate) - Z(False Alarm Rate)`, where Z is the inverse of the standard normal cumulative distribution function.
   - *Crucial SDT Correction*: To prevent infinite d' values, you MUST apply the standard Macmillan & Creelman correction ONLY to rates of 0 or 1.
   - If a rate is exactly `0`, replace it with `0.5 / N`.
   - If a rate is exactly `1`, replace it with `(N - 0.5) / N`.
   - (Where `N` is the total number of `GO` trials for the Hit Rate correction, or the total number of `NOGO` trials for the False Alarm Rate correction).

**Exclusion Criterion:**
Identify and exclude `sub-99`. Their data reflects an automated/continuous keypress (a stuck key). Exclude any participant who meets BOTH of these criteria:
- False Alarm Rate >= 0.90
- Mean Hit RT < 100 ms

**Expected Actions:**
1. Read and parse `~/pebl/data/gng_data.csv`.
2. Compute the required behavioral and SDT metrics for all participants.
3. Flag and exclude `sub-99` according to the exclusion criteria.
4. Calculate group means for all metrics across the *valid* participants only.
5. Save the structured output to `~/pebl/analysis/gng_report.json`.

**Final State:** The JSON report file exists at `~/pebl/analysis/gng_report.json` with the correctly computed values.

## Verification Strategy

### Primary Verification: Programmatic Output Evaluation
A Python verification script will load the expected ground truth and compare it against the agent's generated `gng_report.json`. It will verify the structural validity of the JSON and statistically check the metrics against defined tolerance ranges to account for floating-point arithmetic differences.

### Secondary Verification: Artifact Exclusion Verification
The verifier will explicitly check if `sub-99` (and ONLY `sub-99`) was excluded and verify that the provided reason references the specific logical conditions (FA rate and RT).

### Scoring System

| Criterion | Points | Description |
|-----------|--------|-------------|
| File Existence & Schema | 10 | `gng_report.json` exists and parses as valid JSON |
| Contamination Detection | 20 | `sub-99` is successfully excluded from analysis |
| Error Counts Accurate | 20 | Omission and Commission counts match ground truth exactly |
| SDT Implementation (d') | 25 | d' is correctly computed (within ±0.05), proving boundary correction was applied |
| RT Calculation | 10 | Mean Hit RT is calculated correctly (within ±1.0 ms) |
| Group Aggregation | 15 | Group means exclude the contaminated participant and match ground truth |
| **Total** | **100** | |

**Pass Threshold:** 60 points