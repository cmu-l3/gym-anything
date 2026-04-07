# Task: Workplace Chemical Exposure Protocol

## Overview

**Environment**: GNU Health Hospital Information System (HIS) 5.0
**Domain**: Occupational Health / Industrial Medicine
**Difficulty**: Very Hard
**Patient**: Bonifacio Caput

## Occupational Context

This task reflects the workflow of an occupational health physician managing a workplace chemical exposure incident. Chemical burns in industrial settings require systematic documentation for both clinical management and regulatory compliance (OSHA recordkeeping, workers' compensation). The physician must code the injury with the correct ICD-10 external cause code, document clinical findings, prescribe wound care, order toxicology and baseline labs, update the patient's occupational profile, and arrange close wound follow-up.

## Scenario

**Bonifacio Caput**, a 45-year-old factory maintenance worker, sustained a chemical splash injury to the left hand and forearm from a caustic industrial cleaning agent (sodium hydroxide solution) during routine equipment maintenance. He presented to the occupational health clinic with erythema, blistering, and partial-thickness chemical burns over approximately 5% body surface area. He reports significant pain (7/10), no ingestion, and no respiratory symptoms.

As the occupational health physician, complete the incident documentation: record the chemical burn diagnosis with appropriate ICD-10 coding, perform a clinical evaluation documenting the injury findings and vital signs, prescribe appropriate wound care treatment, order toxicology and baseline laboratory studies, and schedule a wound reassessment follow-up within the standard 3–10 day window.

## Goal (End State)

All five criteria must be documented in GNU Health for Bonifacio Caput:

1. **Chemical burn diagnosis**: ICD-10 T-code (T54.x for corrosive substances, or T20-T32 burn codes) as an active condition
2. **Clinical evaluation**: A documented encounter recording the injury presentation
3. **Wound care prescription**: Silver sulfadiazine, bacitracin, or appropriate topical burn treatment
4. **Toxicology/baseline lab orders**: At least **2** lab orders (CBC for baseline, toxicology screen, metabolic panel)
5. **Wound reassessment follow-up**: Appointment scheduled **3–10 days** from today

## Login Credentials

- **URL**: `http://localhost:8000/`
- **Database**: `health50`
- **Username**: `admin`
- **Password**: `gnusolidario`

## Success Criteria

Score of 70+ (out of 100) to pass. Each criterion is worth 20 points with partial credit.

## Contamination Note

Setup pre-seeds a T-code burn diagnosis on Ana Betz (wrong patient) as a distractor. The verifier validates all records belong to Bonifacio Caput.

## Database Schema Reference

| Table | Key Columns | Purpose |
|-------|------------|---------|
| `gnuhealth_patient_disease` | patient, pathology, is_active | Burn diagnosis |
| `gnuhealth_pathology` | id, code, name | ICD-10 codes |
| `gnuhealth_patient_evaluation` | patient, temperature, heart_rate | Clinical encounter |
| `gnuhealth_prescription_order` | patient, healthprof | Wound care Rx |
| `gnuhealth_patient_lab_test` | patient_id, test_type | Lab orders |
| `gnuhealth_appointment` | patient, appointment_date | Wound follow-up |
