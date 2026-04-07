# Task: real_estate_agent_expenses

## Domain Context

Real estate agents in Canada typically receive both a T4 (base salary/draw from their brokerage) and a T4A (commission income as an independent contractor). This dual-status structure is unique to the real estate profession and requires careful handling: the T4 income is employment income, while the T4A commission income requires Form T2125 with extensive business expense deductions. Allowable deductions include vehicle expenses (with km log proration), home office costs (based on square footage), marketing and advertising, professional dues (RECA, CREB, CREA), and Errors & Omissions insurance. Alberta has no provincial sales tax (PST) and a flat 10% provincial income tax, making it a distinct jurisdiction.

**Occupation relevance**: Accountants and Auditors (O*NET 13-2011.00; importance=86) who specialize in real estate professional returns manage high-value T2125 filings with complex expense portfolios. Tax Preparers (O*NET 13-2082.00; importance=92) encounter real estate agent returns as a common complex filing type.

## Goal

Complete Rodrigo Espinoza's 2024 Canadian personal income tax return using StudioTax 2024. Save the completed return as `rodrigo_espinoza.24t` in `C:\Users\Docker\Documents\StudioTax\`.

Tax documents are in: `C:\Users\Docker\Desktop\TaxDocuments\espinoza\`

## What Success Looks Like

The saved `.24t` return file must contain:
- Rodrigo Espinoza as the taxpayer (Alberta resident, common-law)
- T4 base salary from Century 21 Bamber Realty Ltd. ($36,000)
- T4A commission income from Century 21 ($87,500) entered via Form T2125
- Business expenses entered on T2125 totaling $40,478:
  - Vehicle operating costs (73.1% of $11,410 = $8,342)
  - CCA on Class 10 vehicle ($6,217 business portion)
  - Marketing and advertising ($10,630)
  - Professional fees and dues ($6,770)
  - Home office (12% of home costs = $6,024)
  - Cell phone and office supplies ($1,780)
  - Professional development ($715)
- RRSP contribution ($10,000)
- Charitable donation ($500 to Calgary Humane Society)
- Common-law partner Isabella Morales entered with net income $72,600
- File saved with timestamp after task start

## Application Features Required

This task exercises at least 6 distinct StudioTax features:
1. **T4 slip entry** — base salary with CPP, EI, income tax withheld
2. **T4A slip entry** — commission income (Box 20)
3. **T2125 Business Income form** — extensive expense categories (vehicle, marketing, professional fees, home office)
4. **CCA schedule** — Class 10 declining-balance, business-use portion
5. **Schedule 9 donations** — charitable donation credit (federal + AB)
6. **Schedule 7 RRSP** — RRSP deduction
7. **Common-law partner info** — Alberta province, partner with income

## Verification Strategy

| Criterion | Points | Check |
|-----------|--------|-------|
| File saved with correct name | 15 | `rodrigo_espinoza.24t` exists and > 500 bytes |
| Timestamp valid | 10 | File modified after task start |
| Taxpayer name present | 10 | "Espinoza" + "Rodrigo" in file |
| T4 base salary $36,000 | 10 | String "36000" found |
| T4A commission income $87,500 | 15 | String "87500" found |
| Business expenses (marketing, vehicle, CCA) | 15 | "10630", "8342", "6217" any found |
| RRSP $10,000 and/or donation $500 | 10 | "10000" and/or "500" found |
| Alberta province + common-law partner | 15 | "Alberta"/"AB" + "Morales"/"common-law" found |
| **VLM evaluation** | 25 | Reserved |
| **Total** | **115** | Pass threshold: 60/100 programmatic |

**Score cap**: T4A commission income ($87,500) must be present. Missing it caps score at 55.

## Critical Complexity

- **Dual-employer structure**: Both the T4 AND T4A come from the same employer (Century 21), but with different account numbers (RP0001 vs RP0002). The agent must enter both separately — one as employment income, one as T2125 business income.
- **Extensive expense categorization**: T2125 has many line items. Vehicle operating costs, CCA, home office, marketing, professional dues, and professional development must each go under the correct T2125 category.
- **Alberta jurisdiction**: No provincial sales tax; flat 10% provincial income tax. The agent must select Alberta as the province of residence — different tax calculations than Ontario tasks.
- **No double-deduction**: Cell phone and vehicle expenses are claimed on T2125 only (not also on T777), since all expenses relate to the commission income.
- **Charitable donation**: $500 to a registered charity generates both federal and Alberta donation tax credits via Schedule 9.
- **CCA class 10 truck**: F-150 acquired in 2021, no half-year rule in 2024. CCA = 30% × $28,350 = $8,505; business portion = 73.1% = $6,217.

## Edge Cases

- Agent enters all income as T4 — T4A commission criterion fails and T2125 expenses are missed
- Agent claims T2200/T777 in addition to T2125 expenses — double-deduction error (VLM may flag)
- Agent skips home office expense — partial credit on business expense criterion
- Agent enters partner as spouse instead of common-law — minor error; amounts still present
- Agent enters province as Ontario instead of Alberta — affects tax calculation; province criterion fails

## Source Data

- Scenario file: `C:\workspace\data\scenario_espinoza_realestate.txt`
- RECA fees: Published by Real Estate Council of Alberta (real 2024 rates)
- CREB/CREA dues: Published by Calgary Real Estate Board / CREA (real 2024 rates)
- CRA T2125 guide: T4002 (Business and Professional Income) 2024 — Section 5: Real Estate Agents
- Company names: Real (Century 21 Bamber Realty Ltd., Calgary Humane Society)
- Tax rates: Real 2024 CRA federal and Alberta provincial brackets
