# Forensic Transaction Audit

## Task Overview

Analyze a Q3 2024 transaction ledger (200 transactions) for Greenfield Industries to identify embedded financial irregularities. The agent must perform a forensic analysis detecting duplicate payments, round-number anomalies, below-threshold structuring patterns, and weekend transactions, then produce a comprehensive forensic audit workbook.

## Occupation / Industry

Forensic Accounting / Financial Auditing

## Difficulty

very_hard

## Source Data Description

- **Input file**: `~/Documents/Spreadsheets/transaction_ledger.xlsx` -- a 200-row transaction ledger containing vendor names, amounts, dates, and invoice numbers for Q3 2024.
- **Embedded anomalies** (deterministic, seed=42):
  - 5 duplicate payment pairs (same vendor + amount + invoice within days)
  - 8 round-number transactions >= $10,000
  - 6 just-below-$5,000 threshold (structuring) transactions
  - 4 weekend transactions

## Expected Outcome

A completed forensic audit workbook saved as `~/Documents/Spreadsheets/forensic_audit_report.xlsx` containing:
- Multi-sheet analysis structure (3+ substantive sheets)
- Identified duplicate payment pairs with vendor names
- Flagged round-number / large-amount anomalies
- Detected below-threshold structuring patterns
- Noted weekend transaction anomalies
- Summary statistics (totals, counts, categories)
- Categorization or classification of all anomaly types

## Verification Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| Analysis structure | 1.0 | Multiple substantive sheets demonstrating organized analysis (3+ sheets = full, 2 = partial) |
| Duplicate payment detection | 2.0 | At least 3 of 5 duplicate vendor names identified in anomaly context |
| Round-number anomalies | 1.5 | Round-number or large-amount suspicious transactions flagged with specific amounts |
| Below-threshold structuring | 1.5 | Transactions just below $5,000 approval threshold identified as structuring |
| Weekend transaction anomalies | 1.0 | Weekend or non-business-day transactions detected and flagged |
| Summary statistics | 1.5 | Totals, counts, and numeric summaries of flagged items present |
| Anomaly categorization | 1.5 | Classification of anomaly types with risk/severity/priority labels |

**Total: 10.0 points**

## Success Threshold

A score of 5.0 / 10.0 or higher (normalized to 0.50) is required to pass.
