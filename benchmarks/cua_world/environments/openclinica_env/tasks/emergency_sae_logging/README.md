# Emergency SAE Logging & Unblinding (`emergency_sae_logging@1`)

## Overview
This task simulates a critical clinical trial scenario: handling a Serious Adverse Event (SAE) that necessitates emergency unblinding. The agent must document the unblinding via a discrepancy note, schedule an unscheduled safety event, and log the SAE.

## Rationale
**Why this task is valuable:**
- Tests Unscheduled Event scheduling, a core EDC competency.
- Evaluates the agent's ability to use the Notes & Discrepancies feature (Annotations).
- Clinically relevant: Pharmacovigilance and emergency unblinding documentation are strict regulatory requirements.

**Real-world Context:** A patient (DM-105) in the double-blind Phase II Diabetes Trial presented to the ER with severe hypoglycemia. The PI authorized emergency unblinding. The coordinator must urgently update the EDC system to document the unblinding and log the SAE.

## Task Description

**Goal:** For subject `DM-105` in the Phase II Diabetes Trial, document the emergency unblinding and schedule the SAE event.

**Starting State:** Firefox is open and logged into OpenClinica. Subject `DM-105` is enrolled. The event definition "Unscheduled SAE" is available.

**Expected Actions:**
1. Navigate to the Subject Matrix and locate subject `DM-105`.
2. Add a discrepancy note (Annotation) to DM-105's record containing the keyword `unblinding`.
3. Schedule a new instance of the "Unscheduled SAE" event for DM-105.
4. Add another discrepancy note (Annotation) to DM-105's record (or to the newly scheduled event) containing the exact text `Severe Hypoglycemia`.

**Final State:** DM-105 has an unscheduled event and the required documentation notes.

## Verification Strategy

### Primary Verification: Database State
1. **Unblinding Note:** Queries `discrepancy_note` for "unblinding" linked to DM-105.
2. **Event Scheduled:** Queries `study_event` for the "Unscheduled SAE" event linked to DM-105.
3. **SAE Note:** Queries `discrepancy_note` for "Severe Hypoglycemia".

### Secondary Verification: VLM & Audit Log
- VLM check of final screenshot for OpenClinica UI.
- Audit log check ensures GUI interaction occurred (no direct database manipulation).

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| Unblinding Note | 30 | Discrepancy note containing "unblinding" exists. |
| Event Scheduled | 30 | "Unscheduled SAE" event scheduled for DM-105. |
| SAE Note | 30 | Discrepancy note containing "Severe Hypoglycemia" exists. |
| VLM Check | 10 | OpenClinica UI visible in final screenshot. |
| **Total** | **100** | |

Pass Threshold: 70 points.