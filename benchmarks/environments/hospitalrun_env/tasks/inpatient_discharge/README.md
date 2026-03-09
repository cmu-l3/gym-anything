# Task: Inpatient Discharge Workflow

## Overview

A ward nurse or hospitalist must perform all steps to discharge an inpatient patient. Arthur Jensen has been admitted for a COPD exacerbation and is ready to go home. The discharge process requires the clinician to navigate across four distinct areas of HospitalRun: recording final vitals, documenting a discharge diagnosis, creating discharge medications, and checking out the patient.

## Domain Context

Inpatient discharge documentation is a high-stakes workflow performed by nurses and hospitalists daily. Incomplete documentation (missing vitals, no discharge diagnosis, no medication reconciliation, or failing to close out the visit) creates compliance issues and billing problems. This task reflects the full discharge checklist a clinician must complete before a patient leaves the ward.

## Target Patient

- **Name**: Arthur Jensen
- **Patient ID**: P00014
- **CouchDB ID**: patient_p1_000014
- **Visit CouchDB ID**: visit_p1_000014
- **Date of Birth**: 11/03/1957
- **Sex**: Male
- **Condition**: COPD exacerbation
- **Visit Type**: Inpatient (status: admitted at task start)

## Task Goal

Complete Arthur Jensen's inpatient discharge by performing **all four** steps:

1. **Record final vitals**: BP 132/78, HR 82, RR 20, Temp 37.0°C, O2 Sat 92%, Weight 74 kg, Height 178 cm
2. **Add discharge diagnosis**: Any diagnosis with COPD/chronic obstructive pulmonary/respiratory terminology
3. **Create discharge medication**: Any appropriate respiratory medication (bronchodilator, inhaled corticosteroid, etc.)
4. **Check out the patient**: Mark the inpatient visit as completed/discharged

## Success Criteria

| Criterion | Points | Condition |
|-----------|--------|-----------|
| Vitals recorded | 25 | Vitals doc linked to Arthur Jensen with ≥2 expected values |
| Discharge diagnosis | 25 | Diagnosis with COPD/respiratory keyword linked to Arthur Jensen |
| Discharge medication | 25 | Medication order linked to Arthur Jensen |
| Patient checked out | 25 | Visit status changed to discharged/completed |

**Pass threshold**: 50 points (≥2 of 4 steps)

## Verification Strategy

1. Scans CouchDB for vitals documents linked to patient_p1_000014
2. Scans for diagnosis documents with COPD-related keywords
3. Scans for medication documents linked to patient_p1_000014
4. Directly fetches visit_p1_000014 and checks its `status` or `checkoutDate` fields

## Edge Cases

- Visit starts with `status: "admitted"` — any change toward "completed", "discharged", "checked out", or a checkout date is accepted
- Any respiratory medication is acceptable (the verifier checks for a broad set of COPD-relevant drug names)
- Vitals tolerance: ≥2 of 5 numeric values must appear in the document
