# Task: medical_correspondence_batch

## Overview

**ID**: `medical_correspondence_batch@1`
**Difficulty**: Hard
**Timeout**: 900 seconds | **Max steps**: 120
**Pass threshold**: 55/100

A GP must produce three different medical correspondence documents for three patients in a single session — a referral letter to an endocrinologist, a work accident consolidation certificate, and a referral letter to a cardiologist. Each requires navigating to the correct patient file and using the appropriate MedinTux document module (courrier médical vs. certificat médical).

---

## Professional Context

In French general practice, GPs routinely produce medical correspondence: referral letters (courriers) to specialists, and certificates (certificats médicaux) for social or administrative purposes. MedinTux supports multiple document types with different TypeRub codes:
- **Courrier médical** (20020500 / 90010000): Letters to colleagues or insurers
- **Certificat médical** (20020300): Certificates for work, insurance, sports eligibility

Batching these creates realistic time pressure: the agent must handle three different clinical scenarios, select the right document type for each, and produce clinically coherent content.

---

## Target Patients and Required Documents

### 1. ROUX Céline (born 1977-08-11)
**Clinical context**: Type 2 diabetes (HbA1c 9.2%), hypertension, obesity. Retinopathy screening overdue.
**Required document**: Referral letter (courrier médical) to an endocrinologist requesting specialist management of poorly controlled diabetes.

### 2. FOURNIER Jacques (born 1950-03-08)
**Clinical context**: Work accident on 2026-01-15 — severe right ankle sprain (entorse cheville droite). Patient has been on sick leave since then. Injury is now consolidated.
**Required document**: Medical certificate (certificat médical) confirming consolidation date of 2026-03-01 and fitness for return to work.

### 3. GAUTHIER Hélène (born 1974-06-18)
**Clinical context**: New-onset palpitations (2-3 episodes/week for 1 month, 5-10 min each), hypertension, positive family history of cardiac arrhythmia. ECG at office visit: normal.
**Required document**: Referral letter (courrier médical) to a cardiologist requesting Holter ECG and specialist evaluation.

---

## Scoring (100 pts)

| Patient | Criterion | Points |
|---------|-----------|--------|
| ROUX Céline | Referral letter/courrier document created | 20 |
| ROUX Céline | Letter references endocrinology | 10 |
| ROUX Céline | Letter mentions diabetes/HbA1c | 5 |
| FOURNIER Jacques | Certificate document created | 20 |
| FOURNIER Jacques | Certificate mentions consolidation | 10 |
| GAUTHIER Hélène | Referral letter/courrier document created | 20 |
| GAUTHIER Hélène | Letter references cardiology | 10 |
| GAUTHIER Hélène | Letter mentions palpitations/Holter | 5 |
| **Total** | | **100** |

**Pass threshold**: 55/100 (need approximately 2 of 3 documents with correct content)

---

## Verification Strategy

1. **Baseline recording**: setup_task.sh records max RubriquesHead PrimKey before task starts
2. **Document type check**: Any TypeRub 20020500, 90010000 = letter; 20020300 = certificate
3. **Correct patient check**: Document must be linked to the correct patient GUID
4. **Content check**: Blob text searched for clinical keywords (endocrinolog, consolid, cardiolog, etc.)
5. **New-only filter**: Only rubrics with PrimKey > baseline_pk are considered

---

## MedinTux Document Module Notes

- **Courrier médical**: Typically accessed via the patient file → courrier module → new courrier
- **Certificat médical**: Accessed via the patient file → certificat module
- The `courrier avec choix` (TypeRub=90010000) is also accepted as a letter equivalent
- Content is stored as HTML/XML in RubriquesBlobs

---

## File Structure

```
tasks/medical_correspondence_batch/
├── README.md           # This file
├── task.json           # Task specification
├── setup_task.sh       # Inserts clinical context, records baseline
├── export_result.sh    # Queries new documents per patient
└── verifier.py         # Programmatic scoring
```
