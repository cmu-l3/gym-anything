# Task: Social Health Intake Assessment

## Overview

**Environment**: GNU Health Hospital Information System (HIS) 5.0
**Domain**: Social Work / Community Health / Preventive Care
**Difficulty**: Hard
**Patient**: Matt Zenon Betz

## Occupational Context

This task reflects the real workflow of a social worker, care coordinator, or preventive care nurse completing a comprehensive social determinants of health (SDOH) assessment for a patient. GNU Health's socioeconomic and lifestyle modules are specifically designed for this use case — critical for WHO-aligned community health programs. The patient's occupation, education, lifestyle habits, family medical history, and contact information must all be recorded to complete a thorough SDOH intake.

Per the WHO's approach to social determinants of health, these factors are as important as clinical data for predicting patient outcomes. Incompleteness in social history significantly degrades care coordination quality.

## Scenario

**Matt Zenon Betz** has been referred for a comprehensive health intake assessment. He is Ana Betz's family member who has not had a complete SDOH profile entered. A care coordinator (Dr. Cordara or the admin user) must complete his social health record in GNU Health.

## Goal (End State)

The end state must include **all five** of the following for Matt Zenon Betz:

1. **Socioeconomic data updated**: Education level set to **University** (or equivalent) and Occupation set to **Engineer** (or a similar technical/professional category from the occupation dropdown)
2. **Lifestyle record created**: A new lifestyle record documenting physical activity level (any selection other than "Sedentary"), and tobacco use set to **Non-smoker** (or equivalent negative value)
3. **Family history entry added**: A family history record for **Cardiovascular Disease / Coronary Artery Disease** (ICD-10: I25.x or I21.x or I20.x) for a first-degree relative (parent/sibling)
4. **Contact information updated**: A mobile phone number added to his party record (any valid phone number format)
5. **Preventive care appointment**: A health screening / preventive checkup appointment scheduled with Dr. Cordara within **150 to 200 days** from today (6-month preventive care timeline)

## Login Credentials

- **URL**: `http://localhost:8000/`
- **Database**: `health50`
- **Username**: `admin`
- **Password**: `gnusolidario`

## Key Navigation Notes

- **Socioeconomics tab**: Inside the Patient Health Record form (Patient module → select Matt Zenon Betz → Socioeconomics tab). Contains Occupation, Education, Housing Condition, SES fields.
- **Lifestyle data**: Also accessible from the patient health record (Lifestyle tab or section)
- **Family history**: Patient health record → (look for "Family Diseases" or "Hereditary" section/tab)
- **Contact information**: The party record (accessible via clicking the patient's name link in the patient form) → "Contact Mechanisms" section where phone/email can be added
- **Appointments**: The Appointment module (left sidebar) → New

## Success Criteria

Each of the 5 criteria is worth 20 points = 100 total.
Pass threshold: ≥ 70 pts (completing at least 3–4 of the 5 requirements).

## Verification Strategy

`export_result.sh` queries:
- `party_party.education` for Matt Zenon Betz (should not be null/empty)
- `party_party.occupation` or `gnuhealth_occupation` for the occupation field
- `gnuhealth_patient_lifestyle` for new lifestyle records
- `gnuhealth_patient_family_diseases` for new family history entries
- `party_contact_mechanism` or `gnuhealth_party_contact` for phone contacts
- `gnuhealth_appointment` for preventive care appointment in 150-200 day window

## Database Schema Reference

| Table | Key Columns | Purpose |
|-------|------------|---------|
| `party_party` | id, name, lastname, education, occupation | Patient demographics |
| `gnuhealth_patient_lifestyle` | patient, active, alcohol_intake, smoke... | Lifestyle data |
| `gnuhealth_patient_family_diseases` | patient, relative, pathology | Family medical history |
| `party_contact_mechanism` | party, type, value | Phone/email contacts |
| `gnuhealth_appointment` | patient, appointment_date, healthprof | Appointments |
