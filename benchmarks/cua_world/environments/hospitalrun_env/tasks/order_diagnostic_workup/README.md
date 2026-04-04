# Task: Order Diagnostic Workup for Thyroid Follow-up

## Overview

An endocrinologist or physician must order a complete diagnostic workup for a patient with a thyroid disorder. This requires navigating to the patient's visit and using two distinct sections of HospitalRun's visit management: the Labs section (for blood tests) and the Imaging section (for radiological studies). The clinician must determine which tests are appropriate for thyroid monitoring — not just enter any values.

## Domain Context

Ordering lab and imaging studies is a core physician/NP/PA task in EHR systems. In HospitalRun, lab requests and imaging requests are separate modules within a visit, requiring the agent to navigate to different sections. The task requires domain knowledge about thyroid monitoring (TSH, T4, T3 tests; thyroid ultrasound) as well as EHR navigation skills.

## Target Patient

- **Name**: Elena Petrov
- **Patient ID**: P00011
- **CouchDB ID**: patient_p1_000011
- **Visit CouchDB ID**: visit_p1_000011
- **Date of Birth**: 04/28/1969
- **Sex**: Female
- **Condition**: Hypothyroidism / thyroid disorder
- **Visit Type**: Outpatient (Endocrinology Clinic)

## Task Goal

Order a complete diagnostic workup for Elena Petrov's thyroid follow-up:

1. **Laboratory tests** (≥2 required): TSH, Free T4, Free T3, thyroid antibodies, complete metabolic panel, CBC, or any appropriate blood tests
2. **Imaging study** (≥1 required): Thyroid ultrasound, neck ultrasound, nuclear thyroid scan, or any appropriate imaging

## Starting State

Elena Petrov's outpatient visit exists (visit_p1_000011) with no lab or imaging orders. The task starts at the HospitalRun patient list.

## Success Criteria

| Criterion | Points | Condition |
|-----------|--------|-----------|
| Correct patient | 20 | Elena Petrov confirmed in CouchDB |
| First lab order | 20 | Any lab-type document linked to Elena Petrov |
| Second lab order | 20 | A second distinct lab-type document |
| Imaging order | 40 | Any imaging-type document linked to Elena Petrov |

**Pass threshold**: 60 points (correct patient + imaging + any lab, OR correct patient + both lab orders)

## Verification Strategy

The verifier scans all CouchDB documents linked to patient_p1_000011 and classifies them by type:
- Lab documents: `type=lab` or keywords (tsh, t4, t3, thyroid, metabolic, cbc, panel, blood, etc.)
- Imaging documents: `type=imaging` or keywords (ultrasound, sonogram, scan, mri, ct, etc.)

Both lab and imaging document types are counted independently.
