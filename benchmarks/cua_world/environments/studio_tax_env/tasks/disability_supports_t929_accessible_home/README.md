# Disability Supports Deduction & Accessible Home Exception (`disability_supports_t929_accessible_home@1`)

## Overview
This task evaluates the agent's ability to prepare a Canadian personal income tax return for an employed taxpayer with a severe impairment, requiring optimization between the Disability Supports Deduction (Form T929) and the Medical Expense Tax Credit (Line 33099). It also tests the application of the Home Buyers' Amount (Line 31270) under the special exception for persons eligible for the Disability Tax Credit (DTC), even when they are not first-time home buyers.

## Rationale
**Why this task is valuable:**
- Tests **Form T929 (Disability Supports Deduction)** — a highly specific deduction against earned income that is significantly more valuable than the standard medical expense credit, but frequently missed by preparers.
- Exercises the **Home Buyers' Amount DTC Exception** — claiming the $10,000 credit for an accessible home purchase despite the taxpayer having owned a home in the previous 4 years.
- Tests the distinction between eligible guide dog expenses (Medical) and employment-required adaptive technology (T929).
- Requires handling the **Disability Tax Credit (T2201)** base amount alongside high-income employment (T4).

**Real-world Context:** Elias Thorne is a legally blind software engineer. He requires expensive adaptive technology to perform his job and uses a guide dog. He recently moved from a condo he owned into a new, single-story accessible house. Tax Preparers (O*NET 13-2082.00; importance=92) and Accountants (O*NET 13-2011.00; importance=86) frequently mishandle this specific scenario by dumping all disability-related costs into "Medical Expenses" (a 15% non-refundable credit) instead of utilizing Form T929 (a 100% deduction against his top marginal tax rate). Missing this optimization costs the client thousands of dollars and is a hallmark of inexperienced preparation.

## Task Description

**Goal:** Complete Elias Thorne's 2024 Canadian personal income tax return using StudioTax 2024, correctly allocating his adaptive equipment to Form T929, claiming his accessible home purchase, and saving the return as `elias_thorne.24t`.

**Starting State:** StudioTax 2024 is open on a new blank return. Tax documents and a taxpayer memo are available in `C:\Users\Docker\Desktop\TaxDocuments\thorne\`.

**Taxpayer Profile & Documents:**
- **Name:** Elias Thorne (DOB: 1985-04-12, SIN: 246-810-123)
- **Province:** Nova Scotia (Resident as of Dec 31, 2024)
- **Status:** Single
- **T2201:** Approved for the Disability Tax Credit (Blind).
- **T4 - OceanTech Solutions Inc.:** 
  - Box 14 (Income): $112,500
  - Box 16 (CPP): $3,867.50
  - Box 18 (EI): $1,049.12
  - Box 22 (Tax Deducted): $34,400
- **T2202 - Dalhousie University:** 
  - Box 23 (Eligible tuition fees): $1,500 (Part-time, 2 months)
- **Receipts / Taxpayer Memo Notes:**
  1. *Adaptive Technology (For Employment):* Paid $5,400 for a Braille display and $1,100 for specialized screen reading software required for his job. (Agent must recognize this belongs on Form T929, not medical expenses).
  2. *Guide Dog Expenses:* Paid $3,700 for his certified guide dog (veterinary care and specialized food). (Belongs in Medical Expenses).
  3. *Home Purchase:* Purchased a new accessible single-story home in Halifax on June 1, 2024, for $450,000. He owned a condo in 2022, so he is *not* a first-time home buyer, but the new home is more accessible. (Agent must claim the $10,000 Home Buyers' Amount under the DTC exception).

**Expected Actions:**
1. Enter personal information and set province to Nova Scotia.
2. Indicate that the taxpayer is eligible for the Disability Tax Credit (Line 31600).
3. Enter the T4 slip with all corresponding deductions.
4. Enter the T2202 tuition amount.
5. Complete **Form T929 (Disability Supports Deduction)** for the $6,500 in adaptive technology (Line 21500).
6. Enter the $3,700 guide dog costs under **Medical Expenses** (Line 33099).
7. Claim the $10,000 **Home Buyers' Amount** (Line 31270), applying the disability exception.
8. Save the return.

**Final State:** The optimized return is saved at `C:\Users\Docker\Documents\StudioTax\elias_thorne.24t` with all deductions correctly categorized.

## Verification Strategy

### Primary Verification: Programmatic File Inspection
The verifier script reads the saved `.24t` file to check for the presence of the required tax lines, verifying the agent did not miscategorize the T929 expenses as medical expenses.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| File saved with correct name | 10 | `elias_thorne.24t` exists and > 500 bytes |
| Taxpayer & Province | 10 | "Thorne", "Elias", and Nova Scotia ("NS") found |
| T4 Income | 10 | String "112500" found in file |
| **Form T929 Deduction (CRITICAL)** | 25 | $6,500 found on Line 21500 (T929). *Score fails if lumped into medical.* |
| Medical Expenses | 15 | $3,700 found on Line 33099 for guide dog |
| Home Buyers' Amount | 15 | $10,000 found on Line 31270 |
| Disability Amount Claimed | 5 | Base DTC claimed (Line 31600 presence) |
| Tuition Amount | 10 | $1,500 found (T2202) |
| **Total** | **100** | |

**Pass Threshold:** 65 points. **Score Cap:** If the $6,500 adaptive equipment is entered as a Medical Expense instead of the T929 Disability Supports Deduction, the score is capped at 50 (Fail), as this is a critical professional error that miscalculates the client's tax liability.