# oc_critical_lab_followup — Critical Lab Value Response Protocol

## Overview

**Difficulty**: Very Hard
**Occupation**: Medical Scientist / Clinical Reviewer
**Environment**: OpenClinic GA Hospital Information System

Overnight lab review protocol. The agent must identify all patients with critical laboratory values, schedule urgent follow-up appointments, and apply the medically correct medication response for each — while correctly handling a trap (a patient with a "look-alike" profile who should NOT have medication removed).

## Domain Context

Medical scientists and on-call clinicians review flagged lab results overnight. Standard hospital protocol requires: (1) scheduling urgent follow-up for any critical value, and (2) adjusting medications based on the specific critical threshold breached. Medication decisions require domain knowledge: Insulin for critical hyperglycemia, Folic Acid for critical anemia, and Metformin removal for severe renal failure (lactic acidosis risk). The trap tests whether the agent can discriminate between a patient with Metformin + critical CREAT (must remove) vs. a patient with Metformin + normal CREAT (must keep).

## Task Setup (Seeded State)

Three patients have critical lab results injected by `setup_task.sh`:

| Patient | ID | Lab Code | Value | Threshold | Required Action |
|---|---|---|---|---|---|
| Fatima Al-Rashid | 10003 | GLUC | 450 mg/dL | >400 | Schedule appt + add Insulin Regular (9012) |
| David Okonkwo | 10004 | CBC (Hgb) | 6.1 g/dL | <7.0 | Schedule appt + add Folic Acid 5mg (9011) |
| Li Wei | 10009 | CREAT | 4.8 mg/dL | >4.0 | Schedule appt + REMOVE Metformin (9002) |

**Trap**: David Okonkwo (10004) also has Metformin on his chronic medication list. His CREAT is normal. Metformin must NOT be removed from David — only from Li Wei whose CREAT is critically elevated.

## Expected End State

| Patient | Appointment | Medication Change |
|---|---|---|
| Fatima | ≥1 appt | Insulin Regular (9012) added |
| David | ≥1 appt | Folic Acid (9011) added; Metformin (9002) KEPT |
| Li Wei | ≥1 appt | Metformin (9002) REMOVED |

## Scoring

| Criterion | Points | Condition |
|---|---|---|
| C1: Fatima follow-up scheduled | 15 | appt count >= 1 |
| C2: Fatima Insulin Regular added | 15 | product 9012 count >= 1 |
| C3: David follow-up scheduled | 15 | appt count >= 1 |
| C4: David Folic Acid 5mg added | 15 | product 9011 count >= 1 |
| C5: David Metformin NOT removed (trap) | 10 | product 9002 count >= 1 |
| C6: Li Wei follow-up scheduled | 15 | appt count >= 1 |
| C7: Li Wei Metformin removed | 15 | product 9002 count == 0 |

**Pass threshold**: 70/100
**Do-nothing state**: ~10/100 (C5 passes automatically since Metformin starts present for David) → `passed=False`

## Verification Strategy

- `setup_task.sh` injects critical lab results and pre-existing medication traps into the DB
- `export_result.sh` queries `oc_planning` and `oc_chronicmedications` for all 3 patients
- Result written to `/tmp/oc_critical_lab_followup_result.json`
- `verifier.py` copies JSON via `copy_from_env`, evaluates 7 criteria

## Key Database Tables

- `openclinic_dbo.requestedlabanalyses` — lab results (patientid, analysiscode, resultvalue)
- `openclinic_dbo.oc_planning` — appointments (OC_PLANNING_PATIENTID)
- `openclinic_dbo.oc_chronicmedications` — chronic medications (OC_CHRONICMED_PATIENTID, OC_CHRONICMED_PRODUCTID)
- `openclinic_dbo.oc_products` — medication catalog (OC_PRODUCT_OBJECTID, OC_PRODUCT_NAME)

## Why This Is Very Hard

- Agent is not told which patients have critical values — must review lab results for all
- Must interpret clinical thresholds (GLUC>400, Hgb<7.0, CREAT>4.0) using domain knowledge
- Must navigate 3 separate patients across 3 modules (lab, pharmacy, scheduling)
- The Metformin trap requires understanding renal contraindication specifics
- Removing Metformin from the wrong patient (David instead of Li Wei, or both) loses 25 pts
- No medication names or product IDs provided in the task description
