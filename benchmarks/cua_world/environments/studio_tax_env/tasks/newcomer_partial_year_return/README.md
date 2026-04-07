# Task: newcomer_partial_year_return

## Domain Context

Canada receives approximately 400,000–500,000 new permanent residents annually. Newcomers who arrive mid-year are "part-year residents" for Canadian tax purposes — they report only Canadian-source income earned after their arrival date, and their non-refundable tax credits are prorated based on the number of days they were resident. This is governed by the Income Tax Act and detailed in CRA Guide T4055 (Newcomers to Canada). Filing as a full-year resident when you are a part-year resident is one of the most common and consequential errors in immigrant tax returns.

Additional complexity arises from the First Home Savings Account (FHSA) — a new account type introduced in 2023 that allows first-time home buyers to contribute up to $8,000/year tax-free. A newcomer's T2202 tuition credit, Ontario Trillium Benefit (requiring rent declaration), and a spouse who remained abroad (net income $0 for Canadian purposes) add further layers of complexity.

**Occupation relevance**: Tax Preparers (O*NET 13-2082.00; importance=92) in cities with large immigrant populations (Toronto, Vancouver) serve a disproportionate share of newcomer clients. Accountants and Auditors (O*NET 13-2011.00; importance=86) handle complex newcomer returns for high-income immigrants.

## Goal

Complete Amara Osei-Mensah's 2024 Canadian personal income tax return using StudioTax 2024. Save the completed return as `amara_osei_mensah.24t` in `C:\Users\Docker\Documents\StudioTax\`.

Tax documents are in: `C:\Users\Docker\Desktop\TaxDocuments\osei_mensah\`

## What Success Looks Like

The saved `.24t` return file must contain:
- Amara Osei-Mensah as the taxpayer (Ontario resident, arrived April 1, 2024)
- **Part-year residency correctly entered**: Arrival date April 1, 2024 (275 days resident in 2024)
- T4 employment income from Royal Bank of Canada ($52,800) — employment began after arrival
- RPP pension contribution ($2,640 from T4 Box 20) deducted
- FHSA contribution ($4,000) deducted on Line 20805
- T2202 tuition certificate ($1,800 eligible fees from Toronto Metropolitan University)
- Ontario Trillium Benefit completed (Schedule ON-BEN) with rent paid ($26,550 for 9 months)
- Spouse Kwame Osei-Mensah entered with $0 Canadian net income (remained abroad)
- File saved with timestamp after task start

## Application Features Required

This task exercises at least 6 distinct StudioTax features:
1. **Part-year resident identification** — arrival date entry triggering prorated credits
2. **T4 slip entry** — with RPP contributions (not RRSP)
3. **T2202 tuition certificate** — tuition credit entry
4. **FHSA deduction** — First Home Savings Account (new 2023 account type)
5. **Ontario Trillium Benefit (ON-BEN)** — rent declaration for provincial benefit
6. **Spouse/partner with $0 income** — non-resident spouse treatment
7. **World income declaration** — pre-arrival foreign income (exempt but may need disclosure)

## Verification Strategy

| Criterion | Points | Check |
|-----------|--------|-------|
| File saved with correct name | 15 | `amara_osei_mensah.24t` exists and > 500 bytes |
| Timestamp valid | 10 | File modified after task start |
| Taxpayer name present | 10 | "Osei" or "Mensah" + "Amara" in file |
| T4 employment income $52,800 | 15 | String "52800" found |
| **Part-year residency / arrival date** | 20 | Arrival date "2024-04-01" or part-year markers in file — MOST CRITICAL |
| FHSA contribution $4,000 | 10 | String "4000" found |
| Tuition $1,800 and/or rent $26,550 | 10 | "1800" or "26550" found |
| Spouse Kwame entered | 10 | "Kwame" found (or RPP $2,640 as proxy) |
| **VLM evaluation** | 25 | Reserved |
| **Total** | **115** | Pass threshold: 60/100 programmatic |

**Score cap (CRITICAL)**: If neither the arrival date nor part-year marker is found in the file, score is capped at 45 (below pass threshold). Filing as a full-year resident when the taxpayer is a part-year resident is a critical compliance error that results in overclaimed credits.

## Critical Complexity

- **Part-year residency is the most important and commonly missed element**: An agent that files Amara as a full-year Ontario resident will get many dollar amounts correct but will fundamentally misfile the return. The arrival date (April 1, 2024) must be entered in StudioTax's identification section.
- **FHSA — new account type**: The First Home Savings Account (FHSA) was introduced in 2023. It is a separate deduction line (20805) from RRSP (20800). An agent unfamiliar with this may skip it entirely.
- **RPP vs RRSP**: The T4 Box 20 ($2,640) is a Registered Pension Plan contribution — NOT an RRSP. It deducts on Line 20700, not Line 20800.
- **Spouse abroad**: Kwame Osei-Mensah remained in Ghana until 2025. His Canadian net income is $0. The agent must enter him as a spouse with $0 income (which may unlock a spousal credit), not omit the spouse entry.
- **Ontario Trillium Benefit**: Schedule ON-BEN must be completed for Ontario residents who pay rent. Requires declaring total rent paid for the year.
- **Pre-arrival income**: Amara earned income in Ghana before April 1. This income is NOT reported as Canadian taxable income, but StudioTax may ask for world income to prorate certain provincial credits.

## Edge Cases

- Agent files as full-year resident — most critical error; score capped at 45
- Agent confuses FHSA with RRSP — wrong line number; VLM may flag
- Agent enters RPP as RRSP — wrong deduction type; amounts may still appear in file
- Agent skips ON-BEN rent declaration — criterion 7 partially fails
- Agent omits spouse entirely — criterion 8 fails; affects spousal credit calculation

## Source Data

- Scenario file: `C:\workspace\data\scenario_osei_newcomer.txt`
- CRA Guide T4055: Newcomers to Canada 2024 (real published guide)
- CRA FHSA Guide RC4461: First Home Savings Account 2024 (real published guide)
- T2202 tuition format: CRA T2202 Tuition and Enrolment Certificate 2024
- Ontario Trillium Benefit: CRA Schedule ON-BEN 2024
- Company name: Real (Royal Bank of Canada, Toronto Metropolitan University)
- Tax rates: Real 2024 CRA federal and Ontario provincial brackets; prorated at 275/366 days
