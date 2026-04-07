# Task: Chronic Kidney Disease Progression

## Overview

**Environment**: GNU Health Hospital Information System (HIS) 5.0
**Domain**: Nephrology / Internal Medicine
**Difficulty**: Very Hard
**Patient**: Ana Isabel Betz (PUID: GNU777ORG)

## Occupational Context

This task reflects the workflow of a nephrologist managing a patient with progressive chronic kidney disease in the context of underlying diabetes. CKD staging and management requires integrating laboratory findings (eGFR, albuminuria), establishing the correct ICD-10 stage classification, initiating renoprotective pharmacotherapy, documenting dietary counseling for renal diet compliance, ordering a comprehensive renal monitoring panel, and scheduling interval nephrology follow-up per KDIGO guidelines. This task spans conditions, pharmacy, labs, lifestyle documentation, and scheduling — requiring deep nephrology knowledge.

## Scenario

**Ana Isabel Betz** (PUID: GNU777ORG), a 48-year-old female with a known history of Type 1 diabetes mellitus, has been referred to nephrology after routine labs revealed declining renal function. Her most recent labs show an estimated GFR of 42 mL/min/1.73m² (consistent with CKD Stage 3b) and significant albuminuria (A3 category). She has no prior nephrology documentation in the system.

As the consulting nephrologist, you must complete the CKD evaluation and management plan: formally stage the CKD with the correct ICD-10 code, order a comprehensive renal monitoring panel, initiate renoprotective pharmacotherapy with an ACE inhibitor or ARB, document the dietary counseling session in her lifestyle record (renal diet: low sodium, protein restriction), and schedule a 3-month nephrology follow-up per KDIGO guidelines.

## Goal (End State)

All five criteria must be documented in GNU Health for Ana Isabel Betz:

1. **CKD Stage 3b diagnosis**: ICD-10 code **N18.4** (Chronic kidney disease, stage 4 is N18.4... actually N18.32 for stage 3b, but GNU Health ICD-10 may use N18.3 or N18.4 — any N18 subcode accepted with bonus for N18.4 or N18.3)
2. **Renal monitoring lab panel**: At least **3** lab test orders (creatinine, BUN/urea, electrolytes, phosphorus, or related renal markers)
3. **Renoprotective prescription**: ACE inhibitor (Enalapril, Ramipril) or ARB (Losartan, Valsartan) for albuminuria reduction
4. **Dietary counseling in lifestyle record**: A new lifestyle record documenting dietary modifications (renal diet, low sodium, protein restriction)
5. **Nephrology follow-up appointment**: Scheduled **80–100 days** from today (approximately 3 months per KDIGO Stage 3b monitoring)

## Login Credentials

- **URL**: `http://localhost:8000/`
- **Database**: `health50`
- **Username**: `admin`
- **Password**: `gnusolidario`

## Success Criteria

Score of 70+ (out of 100) to pass. Each criterion is worth 20 points with partial credit.

## Contamination Note

Setup pre-seeds an N18 CKD diagnosis on Roberto Carlos (wrong patient) as a distractor. The verifier validates all records belong to Ana Isabel Betz.

## Database Schema Reference

| Table | Key Columns | Purpose |
|-------|------------|---------|
| `gnuhealth_patient_disease` | patient, pathology, is_active | CKD diagnosis |
| `gnuhealth_pathology` | id, code, name | ICD-10 codes |
| `gnuhealth_patient_lab_test` | patient_id, test_type | Renal panel labs |
| `gnuhealth_prescription_order` | patient, healthprof | ACEi/ARB Rx |
| `gnuhealth_patient_lifestyle` | patient / patient_lifestyle | Dietary counseling |
| `gnuhealth_appointment` | patient, appointment_date | 3-month follow-up |
