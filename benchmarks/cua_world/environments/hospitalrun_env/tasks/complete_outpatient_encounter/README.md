# Task: Complete Outpatient Encounter

## Overview

A nurse or physician must complete all components of an outpatient clinical encounter for Grace Kim, a patient with a history of chronic migraines. This mirrors the real workflow of clinical staff who must close out a visit by documenting vitals, diagnosis, and prescribing treatment — three independent sections of the EHR that must each be completed.

## Domain Context

Completing a patient encounter is a core daily task for registered nurses and physicians. HospitalRun requires the clinician to navigate to a patient, open their active visit, and independently record vitals, add a diagnosis, and create a medication order — each in a separate section of the visit. Failure to complete any one section means the clinical record is incomplete.

## Target Patient

- **Name**: Grace Kim
- **Patient ID**: P00013
- **CouchDB ID**: patient_p1_000013
- **Visit CouchDB ID**: visit_p1_000013
- **Date of Birth**: 09/14/1976
- **Sex**: Female
- **Condition**: Chronic migraines
- **Visit Type**: Outpatient

## Task Goal

Complete Grace Kim's outpatient clinical encounter by performing **all three** of the following:

1. **Record vital signs**: BP 128/84, HR 76, RR 16, Temp 36.8°C, O2 Sat 98%, Weight 61 kg, Height 162 cm
2. **Add a primary diagnosis**: Any diagnosis that includes migraine, headache, or cephalgia terminology
3. **Create a medication order**: Any appropriate migraine treatment medication

## Success Criteria

All three subtasks must be completed and linked to Grace Kim's record:

| Criterion | Points | Condition |
|-----------|--------|-----------|
| Vitals recorded | 33 | Vitals document linked to Grace Kim with ≥2 of 5 expected vital values |
| Diagnosis added | 33 | Diagnosis containing migraine/headache keywords linked to Grace Kim |
| Medication ordered | 34 | Medication document linked to Grace Kim |

**Pass threshold**: 66 points (≥2 of 3 subtasks)

## Verification Strategy

The verifier queries CouchDB for all documents, then:
1. Finds any vitals document linked to Grace Kim (via `patient` field or patient name) containing vital measurement fields; awards 33 points if ≥2 of the specific expected values appear
2. Finds any document linked to Grace Kim containing migraine/headache/cephalgia keywords; awards 33 points
3. Finds any medication-type document linked to Grace Kim; awards 34 points

## Schema Reference

- Patient ID in CouchDB: `patient_p1_000013`
- Visit ID in CouchDB: `visit_p1_000013`
- Vitals docs have fields: `heartRate`, `systolic`, `diastolic`, `weight`, `height`, `temperature`, `o2Sat`, `respiratoryRate`
- Diagnosis docs have fields: `diagnosisDescription` or embedded text
- Medication docs have fields: `medication`, `medicationName`, `quantity`, `frequency`

## Edge Cases

- Agent may record vitals with slightly different field names (the verifier uses keyword matching)
- Any migraine-related medication is acceptable (triptans, NSAIDs, anti-emetics, prophylactics)
- Do-nothing test: all scores = 0 since CouchDB starts with no vitals/diagnosis/medication for Grace Kim
