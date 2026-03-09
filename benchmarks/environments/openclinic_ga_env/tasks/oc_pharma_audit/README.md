# oc_pharma_audit — Pharmacy Medication Safety Audit

## Overview

**Difficulty**: Very Hard
**Occupation**: Clinical Pharmacist
**Environment**: OpenClinic GA Hospital Information System

A monthly medication safety audit task. The agent must review chronic medication lists for four patients, identify three distinct types of medication errors (without being told which patients have errors or what kind), and correct them — while leaving one patient's correct medication untouched.

## Domain Context

Clinical pharmacists routinely conduct medication reconciliation and safety audits on ward patients. This involves:
- Reviewing chronic medication appropriateness (antibiotics are acute medications, not chronic)
- Detecting duplicate prescriptions that create overdose risk
- Cross-referencing laboratory results to identify drug-disease contraindications

## Task Setup (Seeded State)

Four patients have chronic medications in the system:

| Patient | ID | Medication | Product ID | Status |
|---|---|---|---|---|
| Fatima Al-Rashid | 10003 | Amoxicillin 500mg | 9001 | **ERROR**: antibiotic as chronic med |
| Priya Sharma | 10007 | Amlodipine 5mg ×2 | 9004 | **ERROR**: duplicate entry |
| Mohammed Hassan | 10008 | Metformin 500mg | 9002 | **ERROR**: CREAT=4.5 mg/dL (renal contraindication) |
| Li Wei | 10009 | Atorvastatin 20mg | 9005 | CORRECT — decoy, must NOT be removed |

Mohammed Hassan also has a CREAT lab result of 4.5 mg/dL (critical: normal <1.2 mg/dL), which the agent must find to understand the Metformin contraindication.

## Expected End State

After task completion:
- Fatima: Amoxicillin removed (0 entries for product 9001)
- Priya: One of two Amlodipine entries removed (exactly 1 entry for product 9004)
- Mohammed: Metformin removed (0 entries for product 9002)
- Li Wei: Atorvastatin unchanged (≥1 entry for product 9005)

## Scoring

| Criterion | Points | Condition |
|---|---|---|
| C1: Amoxicillin removed (Fatima) | 20 | count(10003, 9001) == 0 |
| C2: Duplicate Amlodipine resolved (Priya) | 20 | count(10007, 9004) == 1 |
| C3: Metformin removed (Mohammed) | 20 | count(10008, 9002) == 0 |
| C4: Atorvastatin intact (Li Wei) | 40 | count(10009, 9005) >= 1 |

**Pass threshold**: 75/100 (≥2 errors fixed + decoy intact)
**Do-nothing state**: 40/100 (C4 always passes in initial seeded state) → `passed=False`

## Verification Strategy

- `export_result.sh` queries `openclinic_dbo.oc_chronicmedications` for each patient×product pair
- Result written to `/tmp/oc_pharma_audit_result.json`
- `verifier.py` copies JSON via `copy_from_env`, evaluates four criteria

## Key Database Tables

- `openclinic_dbo.oc_chronicmedications` — chronic medication records
  - `OC_CHRONICMED_PATIENTID`, `OC_CHRONICMED_PRODUCTID`
- `openclinic_dbo.oc_products` — medication catalog
  - `OC_PRODUCT_OBJECTID`, `OC_PRODUCT_NAME`
- `openclinic_dbo.requestedlabanalyses` — lab results
  - `patientid`, `analysiscode`, `resultvalue`

## Why This Is Very Hard

- Agent is not told which patients have errors — must inspect all four
- Must recognize that antibiotics are inherently short-course (domain knowledge)
- Must find and interpret the CREAT lab value to identify the Metformin contraindication
- Must correctly identify Li Wei's Atorvastatin as appropriate (NOT remove it)
- No UI navigation hints given in the description
