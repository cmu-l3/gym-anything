# Mileage Deduction Calculator Task

**Difficulty**: 🟢 Easy  
**Skills**: Formulas, cell references, business calculations  
**Duration**: 120 seconds  
**Steps**: ~8

## Objective

Calculate tax-deductible mileage for a freelance consultant by adding formulas to compute individual trip deductions and total amounts. This task tests practical spreadsheet usage for real-world business scenarios including formula creation, cell references, and aggregate calculations.

## Task Description

The agent must:
1. Open a mileage log spreadsheet (provided with trip data)
2. Add formulas in the Deduction column to calculate each trip's deduction (Miles × Rate)
3. Add a SUM formula in the TOTAL row for total miles
4. Add a SUM formula in the TOTAL row for total deduction amount
5. Save the file

## Data Structure

| Date       | From        | To              | Purpose           | Miles | Rate   | Deduction |
|------------|-------------|-----------------|-------------------|-------|--------|-----------|
| 2024-01-05 | Home Office | Client Site A   | Client Meeting    | 45    | 0.655  | (formula) |
| 2024-01-12 | Home Office | Downtown Office | Project Review    | 28    | 0.655  | (formula) |
| ...        | ...         | ...             | ...               | ...   | 0.655  | (formula) |
| TOTAL      |             |                 |                   | (SUM) |        | (SUM)     |

## Expected Results

- **Deduction column (G2:G7)** contains formulas like `=E2*F2`, `=E3*F3`, etc.
- **Total Miles (E8 or similar)** contains formula `=SUM(E2:E7)`
- **Total Deduction (G8 or similar)** contains formula `=SUM(G2:G7)`
- All calculated values are mathematically correct

## Verification Criteria

1. ✅ **Deduction Formulas Present**: All trip rows contain formulas (not static values)
2. ✅ **Formula Correctness**: Formulas multiply Miles × Rate
3. ✅ **Total Miles Formula**: TOTAL row has SUM formula for miles
4. ✅ **Total Deduction Formula**: TOTAL row has SUM formula for deductions
5. ✅ **Mathematical Accuracy**: All calculations correct within $0.01 tolerance

**Pass Threshold**: 75% (4/5 criteria must pass)

## Skills Tested

- Formula creation with cell references
- Understanding multiplication operations
- Using SUM function for totals
- Relative vs. absolute cell references
- Business calculation accuracy
- Real-world spreadsheet workflows

## Setup

The setup script:
- Creates a mileage log ODS file with 6 business trips
- Includes Date, From, To, Purpose, Miles, Rate columns (all filled)
- Deduction column is empty (agent must add formulas)
- TOTAL row at bottom with empty cells for totals
- Launches LibreOffice Calc with the file

## Export

The export script:
- Saves the file as `/home/ga/Documents/mileage_log.ods`
- Closes LibreOffice Calc

## Verification

Verifier checks:
1. Deduction column contains formulas (formula string parsing)
2. Formulas follow pattern `=E*F` (miles × rate)
3. Calculated deductions match expected values (math validation)
4. Total row contains SUM formulas
5. All totals are mathematically accurate

## Real-World Context

This task mirrors actual workflows for:
- Freelancers tracking client visits
- Sales representatives logging customer meetings
- Contractors documenting job site travel
- Healthcare workers tracking home visits
- Any self-employed individual maintaining tax records