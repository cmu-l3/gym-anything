# Reassign Subject to New Site (`reassign_subject_site@1`)

## Overview
This task simulates a routine but critical clinical data management workflow: transferring an enrolled subject from a main study to an investigational site due to patient relocation, and updating their subject identifier to match the destination site's nomenclature.

## Rationale
**Why this task is valuable:**
- Tests navigation of OpenClinica's hierarchical study/site structure
- Evaluates the agent's ability to locate specific subjects in the Subject Matrix
- Validates interaction with specialized EDC UI components (the "Reassign" function)
- Accurately reflects real-world multi-center clinical trial operations where subjects move between clinical sites

**Real-world Context:** Subject DM-101 enrolled in the Phase II Diabetes Trial at the main coordinating center. They have since relocated to Boston. To ensure proper monitoring and site-level compliance, the subject's EDC record must be transferred to the Boston Clinic site, and their ID updated to BOS-101.

## Task Description

**Goal:** Transfer subject DM-101 from the parent "Phase II Diabetes Trial" to the "Boston Clinic" site and update their Study Subject ID to BOS-101.

**Starting State:** 
- OpenClinica is open and logged in as `root`.
- Active study is set to "Phase II Diabetes Trial".
- The "Boston Clinic" site is pre-configured in the system.
- Subject "DM-101" is enrolled in the parent study.

**Expected Actions:**
1. Navigate to the Subject Matrix.
2. Find the row for subject `DM-101` and click the "View" or "Reassign" icon.
3. Select "Boston Clinic" from the Study/Site dropdown.
4. Update the Study Subject ID field to `BOS-101`.
5. Confirm and save the reassignment.

**Final State:**
- The subject originally known as `DM-101` is now labeled `BOS-101`.
- The subject's `study_id` reference in the database points to the Boston Clinic site, not the parent study.

## Verification Strategy

### Primary Verification: Database State Checks
The verifier queries the OpenClinica database to check the `study_subject` table:
1. Verifies that `BOS-101` exists.
2. Verifies that `BOS-101` is linked to the `study_id` corresponding to the Boston Clinic.
3. Verifies that `DM-101` no longer exists in the parent study.

### Secondary Verification: VLM Trajectory Analysis
To prevent database-only gaming, the verifier samples frames across the agent's trajectory and asks a Vision Language Model to confirm that the OpenClinica web UI was actively used to perform the reassignment.

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| Subject Renamed | 30 | `study_subject` label updated to BOS-101 |
| Site Reassigned | 40 | `BOS-101` `study_id` matches the Boston Clinic site |
| Old Label Removed | 10 | `DM-101` no longer exists in the parent study |
| VLM Verification | 20 | Trajectory shows GUI interaction with Reassign feature |
| Audit Penalty | -100 | Deducted if changes made without OpenClinica audit logs |
| **Total** | **100** | |

Pass Threshold: 70 points with Database Criteria fully met.