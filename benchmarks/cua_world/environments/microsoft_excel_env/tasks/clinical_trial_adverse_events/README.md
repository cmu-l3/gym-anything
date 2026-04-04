# Clinical Trial Adverse Events - Pharmacovigilance Analysis

**Environment**: microsoft_excel_env
**Difficulty**: Very Hard
**Occupation**: Biostatisticians (SOC 15-2041)
**Industry**: Pharmaceutical / Pharmacovigilance

## Task Overview

The agent receives a pharmacovigilance workbook (`clinical_trial_ae.xlsx`) containing real FDA FAERS (Adverse Event Reporting System) data for two PD-1 immune checkpoint inhibitors: pembrolizumab (Keytruda, Merck) and nivolumab (Opdivo, Bristol-Myers Squibb). The agent must analyze individual case reports, compute comparative safety metrics, identify disproportionality signals, and complete a safety summary report.

## Domain Context

Pharmacovigilance is the science of detecting, assessing, and preventing adverse drug reactions. The FDA FAERS database contains millions of spontaneous adverse event reports submitted by healthcare professionals, consumers, and manufacturers. Disproportionality analysis compares the reporting frequency of adverse events between drugs to identify potential safety signals. Rate ratios greater than 1.5 with meaningful absolute differences suggest a drug-specific signal warranting further investigation.

## Data Sources

**Patient Demographics** (Sheet 1, 100 rows, pre-filled):
- Source: FDA FAERS via OpenFDA API (real individual case safety reports)
- Drug: Pembrolizumab (Keytruda)
- Fields: Case_ID, Drug_Name, Age, Sex, Report_Date, Serious, Country
- 85/100 cases flagged as serious

**Raw AE Data** (Sheet 2, 240 rows, pre-filled):
- Source: FDA FAERS via OpenFDA API (reactions from case reports above)
- Fields: AE_ID, Case_ID, Drug_Name, MedDRA_Term, Outcome, Serious
- 127 unique MedDRA preferred terms

**AE Frequency Comparison** (Sheet 3, 30 terms + TOTAL):
- Source: OpenFDA API aggregate AE term counts
- Pre-filled: MedDRA_Term, Keytruda_Report_Count, Opdivo_Report_Count
- Agent fills: Rate_Ratio, Rate_Difference, Signal_Flag
- Total Keytruda reports: ~90,861; Total Opdivo reports: ~76,705

## Required Analysis

### AE_Frequency_Comparison sheet
For each of 30 MedDRA terms: Rate_Ratio (Keytruda/Opdivo), Rate_Difference (Keytruda - Opdivo), Signal_Flag ('SIGNAL' if Rate_Ratio > 1.5 AND Rate_Difference > 500). Fill TOTAL row.

### Safety_Signal_Report sheet
13 summary metrics including: Total Cases, Total AE Terms, Serious Case Rate (%), Most Reported AE terms, term with highest Rate Ratio, count of signal flags, total report counts.

## Scoring (100 points)

| Criterion | Points | Threshold |
|-----------|--------|-----------|
| Rate_Ratio populated for >= 20 of 30 terms | 20 | Values in [0.1, 10.0] |
| >= 10 Rate_Ratio values correct within 5% | 25 | Correct division formula |
| At least 1 SIGNAL flag present | 15 | Correct threshold applied |
| Total Cases (Keytruda) ~ 100, Serious Rate ~ 85% | 20 | From Patient_Demographics |
| TOTAL row Keytruda sum in [80K, 100K] | 20 | Correct column summation |

**Pass threshold**: 60 points
**Do-nothing score**: 0 (all output cells blank)

## Why This Is Hard

- Agent must work across 4 sheets with different granularity levels
- Rate calculations require understanding ratio vs. absolute difference
- Signal detection requires compound conditional logic (Rate_Ratio > 1.5 AND Rate_Difference > 500)
- Safety report requires aggregating data from multiple sheets
- Real FAERS data has messy MedDRA terms and missing values
- 30 terms x 3 calculations each + 13 summary metrics
