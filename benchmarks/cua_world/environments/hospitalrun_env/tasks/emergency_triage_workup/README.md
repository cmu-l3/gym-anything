# Task: Emergency Triage and Initial Workup

## Overview

An emergency department nurse and physician team must complete the initial workup for a patient presenting with acute abdominal pain. This is a time-sensitive, multi-step clinical workflow: the triage nurse records vitals while the physician simultaneously documents a working diagnosis and orders the standard diagnostic studies. In HospitalRun, all four of these actions happen across different sections of the patient visit.

## Domain Context

Emergency triage and workup is one of the highest-stakes workflows in a hospital. The ACS (Appendicitis Clinical Score) workup requires vitals, CBC with differential, CRP, and abdominal CT or ultrasound — all of which must be ordered and documented before the patient goes for surgical consultation. This task reflects the complete initial documentation a nurse/physician pair must complete within the first 30 minutes of an emergency presentation.

## Target Patient

- **Name**: Priya Sharma
- **Patient ID**: P00015
- **CouchDB ID**: patient_p1_000015
- **Visit CouchDB ID**: visit_p1_000015
- **Date of Birth**: 07/09/1997
- **Sex**: Female
- **Presentation**: Acute right lower quadrant abdominal pain — rule out appendicitis
- **Visit Type**: Emergency

## Task Goal

Complete the emergency triage and initial workup for Priya Sharma:

1. **Record triage vitals**: BP 110/72, HR 98, RR 20, Temp 38.2°C, O2 Sat 99%, Weight 58 kg, Height 165 cm
2. **Add working diagnosis**: Appendicitis, acute abdomen, or right lower quadrant pain
3. **Order at least one lab test**: CBC with differential, CRP, WBC, or any appropriate blood work
4. **Order at least one imaging study**: CT abdomen/pelvis, abdominal ultrasound, or any appropriate imaging

## Starting State

Priya Sharma has an emergency visit document (visit_p1_000015) with no vitals, no diagnosis, no labs, and no imaging. The task starts at the HospitalRun patient list.

## Success Criteria

| Criterion | Points | Condition |
|-----------|--------|-----------|
| Vitals recorded | 25 | Vitals doc linked to Priya Sharma with ≥2 expected values |
| Diagnosis added | 25 | Diagnosis with appendicitis/acute abdomen keywords |
| Lab order placed | 25 | Any lab-type document linked to Priya Sharma |
| Imaging order placed | 25 | Any imaging-type document linked to Priya Sharma |

**Pass threshold**: 75 points (any 3 of 4 steps completed)

## Verification Strategy

1. Scans all CouchDB docs for vitals linked to patient_p1_000015; checks ≥2 expected values
2. Scans for diagnosis docs with appendicitis/acute/abdominal keywords
3. Scans for lab-type docs (type=lab or keywords: cbc, crp, wbc, blood, etc.)
4. Scans for imaging-type docs (type=imaging or keywords: ct, ultrasound, abdomen, etc.)

## Edge Cases

- "Appendicitis", "appendix", "acute abdomen", "RLQ pain", "right lower quadrant" all accepted as diagnosis
- Any blood test (CBC, CRP, metabolic panel) counts as a lab order
- CT, MRI, ultrasound, X-ray all count as imaging
- Subtask ordering doesn't matter — agent may complete in any sequence
