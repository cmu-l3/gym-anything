# Record Patient Smoking Status Change (`record_smoking_status_change@1`)

## Overview

This task tests the agent's ability to update a patient's smoking status in their social history when their tobacco use status changes. This is a critical clinical documentation requirement for quality measure tracking (particularly Meaningful Use/MIPS) and involves navigating to the social history section and accurately recording the status transition.

## Rationale

**Why this task is valuable:**
- Tests navigation to social history documentation within patient chart
- Requires understanding of tobacco use status codes (current/former/never)
- Validates ability to update existing health records accurately
- Critical for clinical quality measure compliance (CMS Measure 138)
- Real-world scenario encountered daily in primary care

**Real-world Context:** A patient who was previously documented as a smoker returns for a follow-up visit and reports they successfully quit smoking 3 months ago. Per clinical quality measures and Meaningful Use requirements, the provider must update the patient's smoking status to "former smoker" with the cessation date.

## Task Description

**Goal:** Update the smoking status for patient Marcus Weber from "Current Every Day Smoker" to "Former Smoker" and document the quit date.

**Patient Details:**
- Name: Marcus Weber
- DOB: 1973-04-07
- Patient ID: 6
- Current smoking status: Current Every Day Smoker (documented in social history)

**Starting State:** 
- OpenEMR is open with the login page displayed
- Firefox browser is maximized
- Patient Marcus Weber exists in the database with documented smoking history

**Expected Actions:**
1. Log in to OpenEMR using credentials admin/pass
2. Search for patient "Marcus Weber" using the patient finder
3. Select the patient to open their chart
4. Navigate to the patient's social history (Demographics > Edit > Social History, OR Clinical > History > Social)
5. Locate the tobacco use/smoking status field
6. Change the status from "Current Every Day Smoker" to "Former Smoker"
7. Enter the cessation date: 2024-09-15 (or approximately 3 months prior to current date)
8. Add a note: "Patient reports quit smoking, using nicotine patches for support"
9. Save the changes

**Final State:** 
- Patient Marcus Weber's social history shows smoking status as "Former Smoker"
- Cessation date is recorded
- The record update is persisted to the database

## Verification Strategy

### Primary Verification: Database State Check

The verifier will query the database to confirm:
1. Patient's smoking status has been updated from the original value
2. The new status indicates "former" smoker (various encodings accepted)
3. A modification timestamp shows recent update