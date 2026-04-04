# Task: chart_audit_corrections

## Overview

**Role**: Quality Improvement Coordinator
**Difficulty**: Hard
**Timeout**: 600 seconds / 80 steps
**Environment**: FreeMED 0.9.0-rc1 (http://localhost/freemed/)
**Login**: admin / admin

## Background

A monthly chart audit has flagged three patient records with clinical documentation errors. Your job is to log into FreeMED and correct all three charts. Each chart has a different type of error: a demographic entry mistake, a missing allergy, and a gap in the problem list.

## Required Corrections

### Correction 1 — Demographics Fix (30 pts)

**Patient**: Malka Hartmann
**DOB**: 1994-11-26 (ID 12)

The home phone number was entered incorrectly and currently reads `555-0-ERROR`. Update the phone number to the correct value: **413-555-2847**.

### Correction 2 — Missing Allergy (35 pts)

**Patient**: Myrtis Armstrong
**DOB**: 1985-04-08 (ID 16)

Penicillin allergy is missing from her electronic chart despite being documented in her paper intake form. Add the following allergy:
- **Allergen**: Penicillin
- **Reaction**: anaphylaxis
- **Severity**: severe

### Correction 3 — Problem List Gap (35 pts)

**Patient**: Arlie McClure
**DOB**: 1971-03-06 (ID 17)

Type 2 Diabetes Mellitus is missing from his active problem list. This was identified in the audit because his prescriptions include Metformin, but no corresponding diagnosis is documented. Add the diagnosis:
- **ICD Code**: 250.00
- **Diagnosis**: Type 2 Diabetes Mellitus
- **Onset Date**: 2019-03-15

## Scoring

| Criterion | Points | Requirement |
|-----------|--------|-------------|
| Demographics fix | 30 | Phone updated to 413-555-2847 |
| Penicillin allergy | 35 | Allergy documented with reaction/severity |
| Diabetes diagnosis | 35 | ICD 250.00 in problem list |
| **Total** | **100** | Pass ≥ 70 |

## Notes

- All three corrections are independent — partial credit is awarded for each correct fix
- Navigate to each patient's chart separately using FreeMED's patient search
- The allergy and problem list modules are accessible from within each patient chart
- Demographics can be updated through the patient's profile/demographics section
