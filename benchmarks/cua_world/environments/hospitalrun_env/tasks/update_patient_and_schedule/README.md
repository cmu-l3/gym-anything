# Task: Update Patient Demographics and Schedule Follow-up

## Overview

A medical receptionist or clinic coordinator must update a patient's contact information and book a follow-up appointment in the same workflow session. This reflects a common front-desk task where a patient calls, reports they have moved or changed phone number, and simultaneously requests a follow-up for an ongoing condition.

## Domain Context

Patient demographic maintenance and appointment scheduling are core responsibilities of healthcare administrative staff. In HospitalRun, editing a patient record and creating an appointment are two completely separate workflows — the administrator must navigate to the patient, edit the record and save, then navigate to Scheduling to book the appointment. Neither step can be done from the same screen.

## Target Patient

- **Name**: Robert Kowalski
- **Patient ID**: P00006
- **CouchDB ID**: patient_p1_000006
- **Date of Birth**: 03/22/1971
- **Sex**: Male
- **Condition**: Chronic back pain
- **Visit Type**: Outpatient

## Task Goal

Perform **both** of the following for Robert Kowalski:

1. **Update contact information**:
   - New phone: `617-555-0284`
   - New address: `845 Oak Street, Boston, MA 02101`

2. **Schedule a follow-up appointment**:
   - Appointment type: `Outpatient`
   - Date: any date between 03/01/2026 and 04/30/2026
   - Reason: `Back pain follow-up` (or similar back pain terminology)

## Starting State

Robert Kowalski's record starts with outdated contact info (old Springfield, IL address; old phone number). No back pain follow-up appointment exists.

## Success Criteria

| Criterion | Points | Condition |
|-----------|--------|-----------|
| Phone updated | 25 | Patient doc has phone `617-555-0284` |
| Address updated | 25 | Patient doc address contains `Oak Street`, `Boston`, or `845` |
| Appointment scheduled | 50 | Appointment linked to Robert Kowalski with back pain reason and date in range |

**Pass threshold**: 50 points (appointment + one contact update, or both contact updates)

## Verification Strategy

1. Fetches `patient_p1_000006` directly from CouchDB and checks `phone` and `address` fields
2. Scans all docs for appointments linked to Robert Kowalski with a back pain reason; validates date is within March–April 2026
