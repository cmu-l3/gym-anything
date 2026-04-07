# Insurance Claims Fraud Detection

## Domain Context

Accountants and auditors at health insurance companies analyze claims data to detect fraudulent billing patterns. Common fraud schemes include billing for services not rendered, upcoding (billing for more expensive procedures), duplicate claim submissions, and statistically anomalous billing patterns. Benford's Law analysis is a standard forensic accounting technique used to detect fabricated financial data. This task reflects real-world fraud investigation workflows performed by Senior Auditors and Fraud Analysts in the insurance industry.

**Occupation**: Accountants and Auditors (SOC 13-2011)
**Industry**: Insurance / Healthcare
**GDP Contribution**: $5.6B annually

## Task Overview

The CLAIMS schema contains medical claims data with real CMS HCPCS procedure codes. A fraud detection specification document on the desktop describes the statistical tests and business rules to implement:

1. **Read Specification**: Open `/home/ga/Desktop/fraud_detection_spec.txt` to understand the required detection rules.
2. **Implement FRAUD_DETECTION_PKG**: Create a PL/SQL package with:
   - `BENFORD_ANALYSIS`: Pipelined table function returning first-digit distribution vs expected Benford's Law percentages with chi-square test statistic
   - `FIND_STATISTICAL_OUTLIERS`: Function finding claims > 3 standard deviations above provider mean
   - `DETECT_DUPLICATES`: Procedure flagging same patient + procedure + date within 7 days
   - `DETECT_UPCODING`: Procedure comparing provider code distribution against population average
3. **Create FRAUD_FLAGS Table**: Store detection results with claim_id, flag_type, severity, details.
4. **Run All Detection**: Populate FRAUD_FLAGS by executing all detection procedures.
5. **Create FRAUD_SUMMARY_MV**: Materialized view showing flag counts by type and severity.
6. **Export Report**: Export fraud summary to `/home/ga/fraud_report.csv`.

## Credentials

- Claims schema: `claims_analyst` / `Claims2024`
- System: `system` / `OraclePassword123`

## Success Criteria

- FRAUD_DETECTION_PKG exists with valid package body
- BENFORD_ANALYSIS uses pipelined table function
- All 4 detection functions/procedures exist
- FRAUD_FLAGS table populated with detected fraud
- At least 2 fraud types detected (Benford's Law, outliers, duplicates, upcoding, temporal)
- FRAUD_SUMMARY_MV materialized view exists
- CSV exported to `/home/ga/fraud_report.csv` with flag type data
- SQL Developer GUI was used

## Verification Strategy

- **Package**: ALL_OBJECTS and ALL_PROCEDURES checked for package and components
- **Pipelined**: ALL_SOURCE text checked for PIPELINED keyword
- **Fraud flags**: Direct COUNT queries on FRAUD_FLAGS grouped by flag_type
- **Summary MV**: ALL_MVIEWS checked for existence
- **CSV**: File existence, size, and content keywords verified
- **GUI**: SQL history, MRU cache, active sessions

## Schema Reference

```sql
CLAIMS_ANALYST.PROVIDERS (provider_id, provider_name, npi_number, specialty, state, city, zip_code, enrollment_date)
CLAIMS_ANALYST.PATIENTS (patient_id, patient_name, date_of_birth, gender, zip_code, insurance_plan, enrollment_date)
CLAIMS_ANALYST.PROCEDURE_CODES (procedure_code, description, category, base_rate, modifier_allowed)
CLAIMS_ANALYST.CLAIMS (claim_id, provider_id, patient_id, procedure_code, claim_date, service_date, amount, units, diagnosis_code, claim_status, adjudication_date, paid_amount)
CLAIMS_ANALYST.FRAUD_FLAGS (flag_id, claim_id, flag_type, severity, detection_date, details, reviewed)
```

## Real Data Sources

- Procedure codes from CMS HCPCS (Healthcare Common Procedure Coding System)
- Fee schedule amounts based on CMS Medicare Physician Fee Schedule
- Fraud patterns based on HHS-OIG published fraud indicators

## Difficulty: very_hard

The agent must independently:
- Read and interpret a specification document to understand requirements
- Implement Benford's Law analysis with chi-square statistic calculation
- Create Oracle object types for pipelined table function returns
- Implement statistical functions (STDDEV, mean, z-scores) in PL/SQL
- Understand medical billing fraud patterns
- Design a complete PL/SQL package with multiple interdependent components
