# Loan Portfolio Risk Scoring Model

**Environment**: libreoffice_calc_env
**Difficulty**: very_hard
**Occupation**: Credit Risk Analyst / Loan Officer
**Industry**: Banking / Financial Services

## Scenario

A regional bank's credit risk department has a partially-built loan portfolio spreadsheet. The data entry team populated 20 loan records with borrower attributes, but the financial analysis formulas were never completed. Regulators require the bank to maintain documented risk scores and expected loss calculations for all loans in the portfolio.

The spreadsheet contains:
- **Sheet "Loan Portfolio"**: 20 loan records with raw data (loan amount, rate, term, credit score, DTI ratio, LTV ratio). Five calculation columns are empty.
- **Sheet "Risk Parameters"**: The bank's proprietary risk scoring weight table and category thresholds.
- **Sheet "Portfolio Summary"**: A dashboard with blank summary cells requiring cross-sheet formulas.

## Task Difficulty Justification (very_hard)

The task description does not specify:
- The exact formulas to use (agent must apply financial knowledge)
- Which LibreOffice functions to use
- The specific risk model logic (agent must read the Parameters sheet)

The agent must independently understand the risk model from the Parameters sheet, implement correct financial formulas (PMT, conditional scoring), and build cross-sheet references.

## Required Formulas

### Monthly Payment (PMT)
`=PMT(C2/12, D2, -B2)` — standard amortization formula

### Risk Score
Composite of three sub-scores from the Parameters sheet:
- Credit Score Component (E-column lookup)
- DTI Ratio Component (F-column lookup)
- LTV Ratio Component (G-column lookup)
Total Risk Score = sum of three components (range 3.0–13.5)

### Risk Category
- Score ≤ 4.5: "Low Risk"
- Score ≤ 7.0: "Moderate Risk"
- Score ≤ 9.5: "High Risk"
- Score > 9.5: "Critical Risk"

### Expected Loss
= LoanAmount × DefaultRate (from Parameters sheet based on category)

## Scoring

| Criterion | Points |
|-----------|--------|
| PMT formulas correct (≥15/20 within 2%) | 25 |
| Risk scores in correct range 3.0–13.5 (≥14/20) | 15 |
| Risk categories correctly assigned (≥14/20) | 25 |
| Expected loss column populated (≥14/20 non-zero) | 15 |
| Portfolio Summary sheet has non-zero totals | 10 |
| File saved as .xlsx or .ods (not the original partial file) | 10 |
| **Total** | **100** |
| **Pass threshold** | **65** |

## Feature Matrix

| Feature | Used |
|---------|------|
| PMT financial function | ✓ |
| VLOOKUP / nested IF for scoring | ✓ |
| Cross-sheet references | ✓ |
| Conditional logic | ✓ |
| Credit risk domain knowledge | ✓ |
