# Lease Portfolio NPV Analysis

**Environment**: microsoft_excel_env
**Difficulty**: Very Hard
**Occupation**: Financial Analysts (SOC 13-2051)
**Industry**: Commercial Real Estate / REIT Management

## Task Overview

The agent receives a commercial real estate portfolio workbook (`lease_portfolio.xlsx`) with 12 properties spanning office, industrial, retail, medical, multifamily, and mixed-use asset classes. The agent must project 10-year NOI streams with annual rent escalations and vacancy adjustments, compute NPV at 8% discount rate and IRR for each property, and complete portfolio-level metrics including WALT and value flags.

## Domain Context

Net Operating Income (NOI) projections and NPV/IRR analysis are fundamental to commercial real estate valuation. Cap rate (Capitalization Rate) = NOI / Property Value, so implied value = NOI / Cap Rate. Weighted Average Lease Term (WALT) measures portfolio duration risk. Tenant improvement (TI) allowances and free rent periods represent upfront landlord costs that reduce IRR.

## Data Sources

**Lease Schedule** (Sheet 1, 12 properties, pre-filled):

Cap rates from **CBRE Americas Cap Rate Survey H2 2023**:
- Source: https://www.cbre.com/insights/books/us-cap-rate-survey-h2-2023
- Class A Office: 6.25%, Industrial: 5.75%, Retail Strip: 7.25%, Medical Office: 6.75%, Multifamily: 5.50%, Mixed Use: 6.25%, Flex/R&D: 7.00%

Rents and operating expenses from **JLL US Office Market Statistics Q4 2023**:
- Source: https://www.us.jll.com/en/trends-and-insights/research
- Class A Office: $42-52/sqft/yr, Industrial: $9.50/sqft, Retail NNN: $28-30/sqft

TI allowances from **JLL Fit-Out Cost Guide 2023**:
- Office: $45-70/sqft, Industrial: $10-15/sqft, Retail: $25-35/sqft

Escalation rates from **CBRE 2023 Lease Surveys**:
- Office: 3.0%, Industrial: 2.5%, Retail: 2.0-3.0%

## Required Analysis

### Cash_Flow_Projection sheet
For each property: 10 years of NOI (Year N = Base_Rent x 12 x (1+Esc%)^(N-1) x (1-Vac%) - Opex x SqFt), TI cost (SqFt x TI/sqft), free rent cost (Rent x Months), NPV at 8%, IRR. PORTFOLIO TOTAL row.

### Portfolio_Metrics sheet
WALT (NOI-weighted average remaining lease term from 1/15/2024), remaining lease months, current annual NOI, implied value (NOI/CapRate), NOI/sqft, cost/sqft, Value_Flag (UNDERVALUED if cap >= 7.0%, PREMIUM if cap <= 5.5%).

## Expected Values

- Portfolio total Year 1 NOI: ~$10,015,000
- Value flags: 4 UNDERVALUED (PROP-03, 08, 11 at 7.25%; PROP-12 at 7.0%) + 1 PREMIUM (PROP-06 at 5.5%) = 5 flags

## Scoring (100 points)

| Criterion | Points | Threshold |
|-----------|--------|-----------|
| Year 1 NOI for >= 10 of 12 properties | 20 | Values in [$100K, $3M] |
| >= 6 Y1 NOI values within 12% of ground truth | 25 | Correct NOI formula |
| >= 2 Value Flags (UNDERVALUED/PREMIUM) | 15 | Correct cap rate thresholds |
| Portfolio total Y1 NOI in [$8M, $12M] | 20 | Expected ~$10M |
| >= 6 NPV values present | 20 | Values in [$1M, $50M] |

**Pass threshold**: 60 points
**Do-nothing score**: 0 (all output cells blank)

## Why This Is Hard

- 10-year NOI projection requires compounding escalation formula per property
- NPV requires discounting 10 cash flows at 8% per property
- IRR requires setting up initial investment (TI + free rent) as negative Year 0 cash flow
- WALT requires NOI-weighted average of remaining lease terms
- Properties have different asset types with different vacancy rates and opex structures
- 12 properties x 10 years = 120 NOI calculations plus NPV/IRR for each
