# Task: Tuberculosis Contact Investigation

## Overview

**Environment**: GNU Health Hospital Information System (HIS) 5.0
**Domain**: Public Health / Infectious Disease Epidemiology
**Difficulty**: Very Hard
**Patient**: Matt Zenon Betz

## Occupational Context

This task reflects the workflow of a public health epidemiologist managing an active pulmonary tuberculosis case. TB is a mandatory notifiable disease, and confirmed cases require immediate initiation of the standard 4-drug RIPE regimen (Rifampin, Isoniazid, Pyrazinamide, Ethambutol), microbiological confirmation through sputum cultures, household contact investigation for at-risk family members, and scheduled treatment response evaluation. This task spans the disease registry, pharmacy, laboratory, family history, and scheduling modules — requiring deep clinical and public health knowledge.

## Scenario

**Matt Zenon Betz**, a 42-year-old male, presented with a 3-week history of productive cough, night sweats, unintentional weight loss, and low-grade fever. Chest X-ray revealed right upper lobe infiltrates with cavitation. Sputum acid-fast bacilli (AFB) smear returned positive. He has been confirmed as having **active pulmonary tuberculosis**.

As the public health epidemiologist, you must initiate the TB management protocol: document the TB diagnosis with the correct ICD-10 code, start the standard intensive-phase RIPE regimen (at least 3 of the 4 drugs), order confirmatory sputum cultures, document household contact exposure for at-risk family members (Matt's sister Ana Betz lives in the same household), and schedule the 2-week treatment response evaluation.

## Goal (End State)

All five criteria must be documented in GNU Health for Matt Zenon Betz:

1. **Active pulmonary TB diagnosis**: ICD-10 code **A15** (or subcode A15.0, A15.3, etc.) as an active condition
2. **RIPE regimen**: At least **3 of 4** anti-TB medications prescribed — Rifampin (Rifampicin), Isoniazid, Pyrazinamide, Ethambutol
3. **Sputum/microbiological lab orders**: At least **2** laboratory orders (AFB culture, sputum smear, or related tests)
4. **Household contact documentation**: Family disease history entry documenting TB exposure for a first-degree relative (household contact investigation)
5. **Treatment response follow-up**: Appointment scheduled **10–21 days** from today for initial treatment response evaluation

## Login Credentials

- **URL**: `http://localhost:8000/`
- **Database**: `health50`
- **Username**: `admin`
- **Password**: `gnusolidario`

## Success Criteria

Score of 70+ (out of 100) to pass. Each criterion is worth 20 points with partial credit.

## Contamination Note

Setup pre-seeds a J06 (upper respiratory infection) diagnosis on Bonifacio Caput as a respiratory-code distractor. The verifier validates all records belong to Matt Betz.

## Database Schema Reference

| Table | Key Columns | Purpose |
|-------|------------|---------|
| `gnuhealth_patient_disease` | patient, pathology, is_active | TB diagnosis |
| `gnuhealth_pathology` | id, code, name | ICD-10 codes |
| `gnuhealth_prescription_order` | patient, healthprof | RIPE prescriptions |
| `gnuhealth_prescription_order_line` | name (FK to order), medicament | Drug details |
| `gnuhealth_patient_lab_test` | patient_id, test_type | Lab orders |
| `gnuhealth_patient_family_diseases` | patient, pathology | Contact tracing |
| `gnuhealth_appointment` | patient, appointment_date | Follow-up |
