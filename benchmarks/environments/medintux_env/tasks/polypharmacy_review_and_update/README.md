# Task: Polypharmacy Review and Update

## Overview

**Difficulty**: Hard
**Environment**: MedinTux (French general practice EMR, Wine/MySQL)
**Occupation context**: General Practitioner / Médecin Généraliste

This task simulates a realistic GP workflow: a medication safety review triggered by a pharmacist alert. Four patients in the practice have active prescriptions containing a dangerous medication combination or allergy conflict. The agent must open each patient's complete medical file, identify the specific safety problem present, create a corrected prescription, and document the change in a consultation note.

## Professional Context

Polypharmacy review is a critical routine task for French GPs. The *Haute Autorité de Santé* (HAS) recommends periodic medication review for all patients with ≥5 active medications. Common issues detected include:
- Dual RAAS blockade (ACE inhibitor + ARB), classified as Class III Harm by ACC/AHA 2017
- NSAID prescription in patients with documented NSAID allergy
- Duplicate prescriptions from different specialists (e.g., two beta-blockers)
- Metformin in severe chronic kidney disease (DFG < 30 ml/min; contraindicated per ANSM guidelines)

## Task Goal

For each of the four flagged patients:
1. Open their medical file in MedinTux
2. Review their terrain (allergies/antecedents) and active prescriptions
3. Identify the specific medication safety issue
4. Create a new corrected ordonnance (prescription) that resolves the issue
5. Add a consultation note documenting the change and the clinical rationale

## Target Patients

| Patient | DOB | Issue type |
|---------|-----|------------|
| MARTIN Sophie | 1985-03-22 | Dual RAAS blockade |
| BERNARD Pierre | 1968-11-30 | NSAID allergy conflict |
| MOREAU Francois | 1955-12-01 | Duplicate beta-blockers |
| LEROY Isabelle | 1979-04-15 | Metformin in severe renal insufficiency |

## Verification Strategy

The verifier queries RubriquesHead for new entries (TypeRub=20020100 for prescriptions, TypeRub=20030000 for consultations) created after task start timestamp, per patient GUID.

| Criterion | Points |
|-----------|--------|
| MARTIN Sophie: new prescription | 20 |
| BERNARD Pierre: new prescription | 20 |
| MOREAU Francois: new prescription | 20 |
| LEROY Isabelle: new prescription | 20 |
| ≥2 patients with new consultation note | 10–20 |

**Pass threshold**: 60 points

## Database Reference

- `DrTuxTest.RubriquesHead`: `RbDate_IDDos` (patient GUID), `RbDate_TypeRub` (20020100=prescription, 20030000=consultation, 20060000=terrain), `RbDate_Date` (timestamp)
- `DrTuxTest.RubriquesBlobs`: `RbDate_DataRub` (HTML/XML blob with prescription text)
- `DrTuxTest.IndexNomPrenom`: patient index by name
