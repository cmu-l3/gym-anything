# Administrative Data Invalidation and Restoration (`administrative_data_invalidation@1`)

## Overview
This task evaluates the agent's ability to perform precise, targeted data cleaning operations at the Event and CRF levels in OpenClinica. The agent must act as a Clinical Data Manager to soft-delete logically impossible data (a pregnancy test for a male subject), remove an erroneously scheduled visit for a terminated subject, and restore a valid CRF that was accidentally removed by site staff. 

## Rationale
**Why this task is valuable:**
- Tests navigation of OpenClinica's complex subject-event-CRF hierarchy.
- Requires understanding the difference between modifying an Event (a visit) and an Event CRF (a form within a visit).
- Exercises the "Remove" and "Restore" administrative workflows, which are critical for 21 CFR Part 11 compliance (soft-deletes with audit trails rather than hard database deletes).
- Verifies the agent's ability to execute targeted CRUD operations without affecting surrounding data.

## Task Description

**Goal:** Correct three structural data errors in the Phase II Diabetes Trial by removing an erroneous CRF, removing an erroneous Study Event, and restoring a mistakenly removed CRF.

**Starting State:** Firefox is open and logged into OpenClinica (root / Admin123!) with the Phase II Diabetes Trial (`DM-TRIAL-2024`) as the active study. 
- Subject **DM-102** (Male) has an erroneously added and completed "Pregnancy Status" CRF in his "Baseline Assessment" event.
- Subject **DM-104** (Discontinued) has an erroneously scheduled "Week 8 Follow-up" event.
- Subject **DM-101** (Active) had their "Vital Signs" CRF in the "Baseline Assessment" event accidentally removed (deleted) by a coordinator.

**Expected Actions:**
1. Navigate to the Subject Matrix or View Subjects screen for the Phase II Diabetes Trial.
2. Locate subject **DM-102**. Access their "Baseline Assessment" event and use the administrative tools to **Remove** (invalidate) the "Pregnancy Status" CRF. Leave the other CRFs in that event intact.
3. Locate subject **DM-104**. Use the administrative tools to **Remove** the entire "Week 8 Follow-up" Study Event.
4. Locate subject **DM-101**. Access their "Baseline Assessment" event, view the removed records, and **Restore** the "Vital Signs" CRF back to active/completed status.

## Verification Strategy

### Primary Verification: Database State Checks
The verifier script (`verifier.py`) reads the output of `export_result.sh`, which queries the PostgreSQL database for the status of the three specific entities:

1. **CRF Removal (DM-102)**: Queries `event_crf` table status. Checks that `status_id = 5` (Removed).
2. **Event Removal (DM-104)**: Queries `study_event` table status. Checks that `status_id = 5` (Removed).
3. **CRF Restoration (DM-101)**: Queries `event_crf` table status. Checks that `status_id = 1 or 2` (Available/Completed).

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| DM-102 Pregnancy CRF Removed | 30 | `event_crf` status for Pregnancy Status is 5 (Removed) |
| DM-104 Week 8 Event Removed | 30 | `study_event` status for Week 8 Follow-up is 5 (Removed) |
| DM-101 Vital Signs CRF Restored | 30 | `event_crf` status for Vital Signs is 2 (Completed) or 1 (Available) |
| Collateral Damage Avoided | 10 | DM-102's Vital Signs CRF remains Completed |
| Audit Log Penalty | -100 | Applied if DB states changed but no matching UI audit logs exist |
| **Total** | **100** | |