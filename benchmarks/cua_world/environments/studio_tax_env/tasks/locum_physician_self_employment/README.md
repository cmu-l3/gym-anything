# Task: locum_physician_self_employment

## Domain Context

Physicians in Canada frequently work across multiple income streams: primary hospital employment (T4) and locum/independent practice income (T4A via T2125). This dual-income structure is one of the most common complex scenarios in Canadian medical professional tax preparation. The self-employment (locum) portion requires Form T2125 for professional income, with deductible expenses including CPSO registration fees, CME conference travel, malpractice insurance top-up, and medical reference materials. The RRSP contribution is at the maximum permitted limit — a critical accuracy requirement. High-income physicians are also subject to Ontario surtax and the married spousal credit calculation.

**Occupation relevance**: Accountants and Auditors (O*NET 13-2011.00; importance=86) preparing medical professional returns is a high-value engagement area. Tax Preparers (O*NET 13-2082.00; importance=92) increasingly serve locum physician clients through tax clinics and online services.

## Goal

Complete Dr. Aisha Kamara's 2024 Canadian personal income tax return using StudioTax 2024. Save the completed return as `aisha_kamara.24t` in `C:\Users\Docker\Documents\StudioTax\`.

Tax documents are in: `C:\Users\Docker\Desktop\TaxDocuments\kamara\`

## What Success Looks Like

The saved `.24t` return file must contain:
- Aisha Kamara as the taxpayer (Ontario resident, married)
- T4 employment income from Sunnybrook Health Sciences Centre ($145,000) with all associated T4 boxes
- T4A self-employment income from Staffworks Medical Inc. ($48,000) entered via Form T2125
- Professional business expenses ($8,615 total) deducted on T2125
- RRSP contributions of $28,900 (split across two receipts)
- Spouse Kweku Kamara entered with net income of $38,400
- Union dues ($2,100 from T4 Box 44) and RPP ($12,650 from T4 Box 20) properly entered
- File saved with timestamp after task start

## Application Features Required

This task exercises at least 5 distinct StudioTax features:
1. **T4 slip entry** — large employment income with RPP, union dues, health plan premiums
2. **T4A slip entry** — professional self-employment income (Box 20)
3. **T2125 Business Income form** — professional services income with expense categories
4. **Schedule 7 RRSP** — maximum contribution ($28,900) across two receipts
5. **Spouse/family information** — married status with spouse net income entry
6. **Ontario province** — provincial surtax application at high income

## Verification Strategy

| Criterion | Points | Check |
|-----------|--------|-------|
| File saved with correct name | 15 | `aisha_kamara.24t` exists and > 500 bytes |
| Timestamp valid | 10 | File modified after task start |
| Taxpayer name present | 10 | "Kamara" + "Aisha" in file |
| T4 hospital income $145,000 | 15 | String "145000" found |
| T4A locum income $48,000 | 15 | String "48000" found (or T2125 marker) |
| RRSP contribution $28,900 | 10 | String "28900" found |
| Professional expenses | 10 | "8615" or "1675"+"3200" found; or RPP "12650" |
| Spouse income $38,400 (married filing) | 15 | String "38400" found |
| **VLM evaluation** | 25 | Reserved |
| **Total** | **115** | Pass threshold: 60/100 programmatic |

**Score cap**: Both T4 ($145,000) AND T4A ($48,000) must be present. Missing either caps score at 55.

## Critical Complexity

- **Dual income**: Agent must recognize that the T4 goes in the T4 section while the T4A goes in T2125 as professional income. Entering both as T4 is incorrect.
- **RRSP at maximum limit**: The combined RRSP of $28,900 must match the deduction limit from the 2023 NOA. Two separate receipts must be entered on Schedule 7.
- **Professional expense categories**: CPSO registration fee, CME conference (travel + registration + hotel), medical subscriptions, and CMPA locum rider must each be entered under the correct T2125 expense line items.
- **Married status**: Kweku Kamara's net income ($38,400) must be entered. Since his income exceeds the basic spousal credit, the spousal credit is $0 — but the entry is still required for correct calculation.
- **RPP vs RRSP**: T4 Box 20 ($12,650 RPP) is a registered pension plan contribution — NOT an RRSP. These are separate deductions on different lines.

## Edge Cases

- Agent enters all income as T4 — fails T4A criterion and T2125 expenses are missing
- Agent forgets second RRSP receipt — $28,900 total not achieved
- Agent skips spouse entry — criterion 8 fails; affects spousal credit calculation
- Agent enters CPSO fee under wrong T2125 category — VLM may flag; programmatic check passes if amounts present

## Source Data

- Scenario file: `C:\workspace\data\scenario_kamara_physician.txt`
- CPSO fees: Published by College of Physicians and Surgeons of Ontario (real 2024 rates)
- CMPA membership structure: Canadian Medical Protective Association published rates
- CRA T2125 guide: T4002 (Business and Professional Income) 2024
- Company names: Real (Sunnybrook Health Sciences Centre, Staffworks Medical Inc.)
- Tax rates: Real 2024 CRA federal and Ontario provincial brackets
