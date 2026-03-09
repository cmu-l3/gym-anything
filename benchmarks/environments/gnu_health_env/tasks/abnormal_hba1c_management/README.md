# Task: Abnormal HbA1c Management

## Overview

**Environment**: GNU Health Hospital Information System (HIS) 5.0
**Domain**: Endocrinology / Diabetes Management
**Difficulty**: Hard
**Patient**: Ana Isabel Betz (PUID: GNU777ORG)

## Occupational Context

This task reflects a real workflow faced by endocrinologists and diabetes care teams: managing a patient whose glycated hemoglobin (HbA1c) result comes back critically elevated, indicating poorly controlled diabetes. Per ADA guidelines, an HbA1c ≥ 9% triggers an immediate clinical response: documenting poor glycemic control, intensifying pharmacotherapy, ordering additional monitoring labs, and urgently following up within 2–4 weeks.

## Scenario

Patient **Ana Isabel Betz** (known Type 1 Diabetic with PUID GNU777ORG) had an HbA1c lab test ordered. The result has just arrived: **9.4%** (normal target for T1D is < 7.0%). This critically elevated value requires immediate clinical action from Dr. Cameron Cordara.

## Setup (What setup_task.sh Seeds)

The setup script pre-creates a **pending HbA1c lab test order** for Ana Betz in "requested" state. The agent must:
1. Find this pending lab test
2. Enter the result (9.4%)
3. Complete/validate the lab test record

## Goal (End State)

The end state must have **all four** of the following:

1. **Completed HbA1c lab result**: The pre-seeded HbA1c lab test for Ana Betz must have its result entered (value approximately **9.0–9.8%** is the clinically plausible range) and be marked as validated/completed
2. **New condition or updated condition note**: A diagnosis or condition note reflecting **poorly controlled diabetes** or **uncontrolled Type 1 Diabetes** must be added or updated for Ana Betz (any ICD-10 code in the E10 family: E10, E10.65, E10.9, or similar)
3. **New prescription for insulin dose adjustment**: A new prescription or medication order for insulin (any formulation: Insulin lispro, NovoLog, Humalog, Lantus, Glargine, or regular insulin) — representing intensification of therapy
4. **Urgent follow-up appointment**: Scheduled within **7 to 28 days** from today (urgent follow-up per ADA guidelines for critically elevated HbA1c)

## Login Credentials

- **URL**: `http://localhost:8000/`
- **Database**: `health50`
- **Username**: `admin`
- **Password**: `gnusolidario`

## Key Clinical Details

- **Patient**: Ana Isabel Betz — PUID: GNU777ORG (find her in the Patients list)
- **Physician**: Cordara, Cameron
- **Pre-seeded lab**: A pending HbA1c (GLYCATED HEMOGLOBIN) lab test in "requested" state
- **Expected result value**: 9.4% (or clinically similar — acceptable range is 9.0–9.8%)
- **Condition to document**: Poorly controlled / uncontrolled Type 1 Diabetes — ICD-10 range: E10.x codes
- **Medication to prescribe**: Any insulin product (representing treatment intensification)
- **Follow-up urgency**: 7–28 days (urgent — high HbA1c requires rapid re-assessment)

## Success Criteria

- 25 pts: HbA1c lab result entered (value in 9.0–9.8% range) AND lab test validated/completed
- 25 pts: New/updated diabetes condition record for Ana Betz (E10.x code family) — new since baseline
- 25 pts: New insulin prescription for Ana Betz — new since baseline
- 25 pts: Urgent appointment within 7–28 days — new since baseline

Pass threshold: ≥ 70 pts

## Verification Strategy

`export_result.sh` queries:
- gnuhealth_patient_lab_test for the HbA1c test, checking state and result value
- gnuhealth_lab_test_critearea for the numerical result (the HbA1c% value)
- gnuhealth_patient_disease for new E10.x disease records
- gnuhealth_prescription_order for new insulin prescriptions
- gnuhealth_appointment for urgent follow-up

## Important Note for Agent

Ana Isabel Betz is the **patient** — she is NOT a health professional. The prescribing doctor is **Cordara, Cameron**. Ana Betz has many existing records (10 prescriptions, 18 lab tests from the demo data). The pre-seeded pending HbA1c test will be the most recently created lab test for her in "requested" state.
