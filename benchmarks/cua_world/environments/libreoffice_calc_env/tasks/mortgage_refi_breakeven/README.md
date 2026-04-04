# LibreOffice Calc Mortgage Refinance Decision Calculator Task (`mortgage_refi_breakeven@1`)

**Difficulty**: 🟡 Medium  
**Skills**: Financial formulas (PMT), multi-scenario analysis, break-even calculation, conditional logic  
**Duration**: 180 seconds  
**Steps**: ~25

## Objective

Help a stressed homeowner evaluate three competing mortgage refinance offers by calculating monthly payments, break-even timelines, and long-term interest savings. The agent must use the PMT function, perform break-even analysis, and create decision logic to recommend which offers (if any) make financial sense.

## The Scenario

Sarah is a homeowner who took out a $285,000 mortgage 7 years ago at 6.5% interest. With 23 years remaining on the loan, she's been bombarded with refinance offers. She needs to know:
- Which offers actually save money?
- How long until closing costs are recovered?
- What are the total savings if she sells in 5-7 years?

## Starting State

LibreOffice Calc opens with a pre-filled template containing:
- **Current Mortgage Details:** Original loan, current rate (6.5%), years remaining (23), monthly payment ($1,806)
- **Three Refinance Offers:**
  - Offer 1: 4.75% APR, 30-year term, $4,200 closing costs
  - Offer 2: 4.25% APR, 20-year term, $6,800 closing costs
  - Offer 3: 5.125% APR, 30-year term, $0 closing costs (no-cost refi)

**Note:** Current loan balance is approximately $238,000 (will need to be used for PMT calculations).

## Required Actions

### 1. Calculate New Monthly Payments (Row 16)
For each of the three offers, use the PMT function: