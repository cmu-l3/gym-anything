# Task: gig_economy_self_employment

## Domain Context

Tax preparers and accountants (the top two occupations for StudioTax by economic output) routinely prepare returns for gig economy workers — one of the most complex categories in Canadian personal income tax. Uber and DoorDash drivers receive T4A slips (Box 20: self-employment commissions), not T4 slips. Unlike salaried employees, gig workers must file Form T2125 (Statement of Business or Professional Activities), track vehicle expenses with a mileage log, calculate Capital Cost Allowance (CCA) on their vehicle, and handle CPP obligations on self-employment income. This scenario is one of the most commonly mishandled returns in Canadian tax preparation.

**Occupation relevance**: Accountants and Auditors (O*NET 13-2011.00; importance=86) and Tax Preparers (O*NET 13-2082.00; importance=92) both use StudioTax as a primary compliance and e-filing tool. Gig economy returns represent a large and growing share of complex T2125 filings.

## Goal

Complete Dimitri Papadopoulos's 2024 Canadian personal income tax return using StudioTax 2024. Save the completed return as `dimitri_papadopoulos.24t` in `C:\Users\Docker\Documents\StudioTax\`.

Tax documents are in: `C:\Users\Docker\Desktop\TaxDocuments\papadopoulos\`

## What Success Looks Like

The saved `.24t` return file must contain:
- Dimitri Papadopoulos as the taxpayer (Ontario resident, single)
- Self-employment income from BOTH Uber Canada ($34,840) AND DoorDash Canada ($12,180) entered on Form T2125 — NOT as T4 employment income
- Vehicle operating expenses (83.4% business use)
- Capital Cost Allowance on the Class 10 vehicle
- Net self-employment income correctly calculated after all business expense deductions
- File saved with timestamp after task start

## Application Features Required

This task exercises at least 4 distinct StudioTax features:
1. **T4A slip entry** — self-employment commissions (Box 20)
2. **T2125 Business Income form** — gross revenue, business expenses, CCA schedule
3. **Vehicle expense section** — motor vehicle costs with business-use percentage
4. **CCA schedule** — Class 10 declining-balance calculation, UCC tracking
5. **Personal information & province** — Ontario, single

## Verification Strategy

The `export_result.ps1` script runs after the agent finishes. It kills StudioTax, reads the `.24t` file as UTF-8 bytes, and checks for presence of key strings. The verifier (`verifier.py`) scores:

| Criterion | Points | Check |
|-----------|--------|-------|
| File saved with correct name | 15 | `dimitri_papadopoulos.24t` exists and > 500 bytes |
| Timestamp valid | 10 | File modified after task start timestamp |
| Taxpayer name present | 10 | "Papadopoulos" + "Dimitri" found in file |
| Uber T4A income | 15 | String "34840" found in file |
| DoorDash T4A income | 15 | String "12180" found in file |
| Combined/net income | 10 | "47020" or "35527" or self-employment marker |
| Business expenses (vehicle/CCA) | 10 | "7679" or "2697" found in file |
| File size guard | 15 | File > 5000 bytes (substantive return) |
| **VLM evaluation** | 25 | Reserved for visual verification |
| **Total** | **115** | Pass threshold: 60/100 programmatic |

**Score cap**: If both Uber ($34,840) AND DoorDash ($12,180) income amounts are not present, score is capped at 55 (below pass threshold). This prevents a return for the wrong person from passing.

## Critical Complexity

- **Two T4As, one T2125**: Both T4A slips feed a SINGLE T2125 form (one business). An agent that enters them as two separate businesses or — worse — as T4 employment income will fail criteria 4 and 5.
- **Vehicle CCA**: The half-year rule does NOT apply (vehicle purchased 2019, not 2024). CCA = 30% × UCC $10,780 = $3,234, business portion = 83.4% × $3,234 = $2,697.
- **HST note**: Documents explain that the T4A gross amounts include HST that Uber collects. For T1 purposes, the full amounts are reported as business income. This is a common point of confusion.

## Edge Cases

- Agent may try to enter income as T4 (employment) — verifier checks for amounts but VLM evaluation will flag incorrect form type
- Agent may miss the DoorDash T4A entirely — score cap prevents passing
- Agent may not enter CCA (just operating expenses) — partial credit given if vehicle operating expenses are entered correctly

## Source Data

- Scenario file: `C:\workspace\data\scenario_papadopoulos.txt` (placed on Desktop by setup script)
- Tax rates: CRA 2024 federal and Ontario provincial brackets (real published rates)
- CCA Class 10 rules: CRA Guide T4002 (Business and Professional Income) 2024
- Uber/DoorDash T4A format: CRA T4A Information Guide 2024
- Company names: Real Canadian companies (Uber Canada Inc., DoorDash Canada Inc.)
