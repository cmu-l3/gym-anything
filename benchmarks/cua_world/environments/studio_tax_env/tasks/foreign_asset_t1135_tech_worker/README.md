# High-Net-Worth Foreign Asset Verification (`foreign_asset_t1135_tech_worker@1`)

## Overview
This task evaluates the agent's ability to complete a Canadian personal income tax return for a taxpayer who holds significant foreign property, triggering the mandatory T1135 Foreign Income Verification Statement. The agent must also handle foreign currency conversion (USD to CAD), enter foreign dividend income, and claim the Federal Foreign Tax Credit (Form T2209) for foreign withholding taxes.

## Rationale
**Why this task is valuable:**
- Tests the T1135 Foreign Income Verification Statement — a critical, heavily-audited compliance form in Canadian tax.
- Requires understanding the threshold difference between the T1135 Simplified and Detailed reporting methods (>$250,000 CAD requires Detailed).
- Exercises currency conversion workflows (converting USD brokerage statements to CAD using the Bank of Canada average annual exchange rate).
- Evaluates the interaction between foreign income reporting and the T2209 Foreign Tax Credit.
- Tests a highly realistic and increasingly common demographic: Canadian tech workers holding US-listed Restricted Stock Units (RSUs) in foreign brokerage accounts.

**Real-world Context:** A senior software engineer working for a Canadian subsidiary of a US tech giant holds accumulated company stock in a US-based Morgan Stanley account. Because the cost basis of the shares exceeds $100,000 CAD, they must file a T1135. Furthermore, since the cost exceeds $250,000 CAD, they cannot use the simplified method and must report the exact shares, gross income, and maximum cost during the year via the Detailed reporting method. Failure to file this correctly carries a CRA penalty of $25 per day up to $2,500. Accountants and Auditors (O*NET 13-2011.00; importance=86) are hyper-vigilant about T1135 compliance for their tech clients.

## Task Description

**Goal:** Complete Wei Chen's 2024 Canadian personal income tax return using StudioTax 2024, including the detailed T1135 and foreign tax credit forms. Save the return as `wei_chen.24t` in `C:\Users\Docker\Documents\StudioTax\`.

**Starting State:** StudioTax 2024 is open with a blank return. The tax documents folder (`C:\Users\Docker\Desktop\TaxDocuments\chen\`) contains:
1. A T4 slip from Microsoft Canada Inc.
2. A US 1099-DIV / Consolidated Brokerage Statement from Morgan Stanley.
3. A text note containing the Bank of Canada 2024 average exchange rate.
4. An RRSP contribution receipt.

**Expected Actions:**
1. Enter personal information for Wei Chen (British Columbia resident, single).
2. Enter T4 employment income ($185,000) and associated deductions.
3. Review the Morgan Stanley statement: $12,500 USD in foreign dividends and $1,875 USD in foreign tax withheld.
4. Apply the provided Bank of Canada exchange rate (1.3478) to convert the USD amounts to CAD:
   - Gross Foreign Income = $12,500 × 1.3478 = **$16,848 CAD**
   - Foreign Tax Paid = $1,875 × 1.3478 = **$2,527 CAD**
5. Enter the CAD amounts on a Foreign Income slip / T5 equivalent to trigger the T2209 Foreign Tax Credit.
6. Complete Form **T1135 (Foreign Income Verification Statement)** using the **Detailed Reporting Method** (Category 2: Shares of non-resident corporations):
   - Description: Microsoft Corp.
   - Country Code: USA
   - Maximum cost amount during the year: $350,000 CAD (as per documents)
   - Cost amount at year-end: $350,000 CAD
   - Gross income: $16,848 CAD
7. Enter the RRSP contribution of $15,000.
8. Save the `.24t` return file.

**Final State:** The file `wei_chen.24t` exists, contains the T4 employment income, the converted foreign dividend income, the foreign tax credit, the RRSP deduction, and the fully populated T1135 detailed section.

## Verification Strategy

### Primary Verification: File-based State Check
A PowerShell script will parse the saved `.24t` StudioTax file (which is an XML-like structured format) to verify the presence of the highly specific calculated amounts and form identifiers. 

### Secondary Verification: VLM Trajectory Verification
VLM will evaluate the screenshots taken during the episode to ensure the agent actively opened the T1135 form and entered the data into the Detailed Reporting section, rather than improperly dumping the amounts into generic income lines.

### Scoring System

| Criterion | Points | Description |
|-----------|--------|-------------|
| File existence & name | 10 | `wei_chen.24t` exists in the target directory and >500 bytes |
| Taxpayer identity | 10 | Strings "Chen" and "Wei" and BC province marker found |
| T4 Employment Income | 10 | String "185000" found in the file |
| Foreign Dividend Income (CAD) | 20 | String "16848" found (verifies correct USD->CAD conversion) |
| Foreign Tax Credit (CAD) | 15 | String "2527" found (verifies correct tax conversion and T2209 entry) |
| T1135 Max/Year-End Cost | 15 | String "350000" found (verifies T1135 asset valuation entry) |
| T1135 Corporation/Country | 10 | "Microsoft" and "USA" found in the T1135 context |
| RRSP Contribution | 10 | String "15000" found |
| **Total** | **100** | |

**Pass Threshold:** 70/100 points. 
*Anti-Gaming Cap:* If the converted CAD amounts ("16848" and "2527") are missing, the score is capped at 40. This ensures the agent actually performed the necessary exchange rate calculations rather than copying raw USD numbers.