# Task: new_patient_complex_entry

## Overview

**ID**: `new_patient_complex_entry@1`
**Difficulty**: Hard
**Timeout**: 720 seconds | **Max steps**: 100
**Pass threshold**: 60/100

A new patient is transferring to a French general practice. The GP must create a complete, structured patient file in MedinTux covering demographics, medical history, terrain (allergies), active prescriptions, and a scheduled follow-up appointment.

---

## Professional Context

This task reflects a daily workflow for French GPs: onboarding a transferred patient requires correctly populating all clinical sections of their EMR. MedinTux structures data across multiple distinct modules — patient demographics, terrain (allergies/antecedents), consultation notes, ordonnances (prescriptions), and the agenda — each with its own data entry path. Incorrectly structuring entries (e.g., typing a prescription in the consultation notes rather than creating an ordonnance) results in a partially incomplete file.

---

## Target Patient

| Field | Value |
|-------|-------|
| Last name | BONNET |
| First name | Elise |
| Date of birth | 1958-04-12 |
| Sex | Female |
| Address | 23 Rue de la Fontaine |
| Postal code | 38000 |
| City | Grenoble |
| Phone | 04.76.89.01.23 |
| Social security | 2580438000056 |

---

## Required Components

### 1. Demographics
Complete patient record in IndexNomPrenom + fchpat:
- DOB: 1958-04-12
- Sex: Female
- City: Grenoble (38000)

### 2. Terrain (Allergies & Antecedents)
Rubric TypeRub=20060000:
- **Allergy**: ASPIRINE — Type: Allergique, Status: Actif

### 3. Medical History / Antecedents
Rubric TypeRub=20030000:
- Hypertension artérielle (ICD-10: I10, active, controlled)
- Hypothyroïdie (ICD-10: E03.9, active, treated)

### 4. Active Prescription
Rubric TypeRub=20020100 (ordonnance):
- Ramipril 5mg — 1 comprimé le matin
- Levothyroxine 75 microg — 1 comprimé le matin à jeun
- Amlodipine 5mg — 1 comprimé le soir

### 5. Follow-up Appointment
Agenda entry:
- Date: 2026-04-02
- Time: 09:00
- Duration: 30 minutes
- Type: Consultation
- Note: "Premier bilan nouveau patient"

---

## Scoring (100 pts)

| Criterion | Points |
|-----------|--------|
| Patient created in database | 10 |
| Demographics correct (DOB, sex, city) | 10 |
| Terrain rubric created | 15 |
| + Aspirin allergy documented | 5 |
| Consultation/antecedent rubric created | 10 |
| + Hypertension documented | 5 |
| + Hypothyroïdie documented | 5 |
| Prescription rubric created | 10 |
| + Ramipril in prescription | 5 |
| + Levothyroxine in prescription | 5 |
| + Amlodipine in prescription | 5 |
| Agenda entry created | 10 |
| + Appointment on 2026-04-02 | 5 |
| **Total** | **100** |

**Pass threshold**: 60/100

---

## Verification Strategy

1. **Baseline recording**: setup_task.sh records patient count and agenda max PrimKey before task
2. **Patient creation check**: Query IndexNomPrenom for BONNET/Elise
3. **Demographics check**: Query fchpat for DOB, sex, city
4. **Terrain check**: Query RubriquesHead (TypeRub=20060000) + blob content for "aspirine"
5. **Consultation check**: Query RubriquesHead (TypeRub=20030000) + blob content for "hypertension" and "hypothyro"
6. **Prescription check**: Query RubriquesHead (TypeRub=20020100) + blob content for "ramipril", "levothyrox", "amlodipine"
7. **Agenda check**: Query agenda for BONNET Elise entries with PrimKey > baseline, date 2026-04-02

---

## File Structure

```
tasks/new_patient_complex_entry/
├── README.md           # This file
├── task.json           # Task specification
├── setup_task.sh       # Ensures clean state, records baseline
├── export_result.sh    # Queries all verification data
└── verifier.py         # Programmatic scoring
```

---

## Notes for Task Designers

- The patient BONNET Elise does not exist in the baseline database — she must be created from scratch
- setup_task.sh deletes any pre-existing BONNET Elise records to ensure idempotent re-runs
- The terrain module in MedinTux is accessed via the patient file "antécédents" section
- The ordonnance module is separate from the consultation/antecedent module
- Agenda entries can be created via the patient file agenda tab or the main agenda view
