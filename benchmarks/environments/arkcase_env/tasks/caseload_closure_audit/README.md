# Task: Caseload Closure Audit

## Domain Context

At the end of each supervision term, Probation Officers must formally close completed cases in ArkCase. This is a compliance requirement — open cases that should be closed inflate caseload statistics and can trigger unnecessary follow-up contacts. The closure process requires reviewing each case's supervision end date, confirming the supervisee completed all requirements, adding a closure note, and changing the case status to Closed. This task simulates a quarterly caseload audit.

## Goal

Six complaint records exist representing active probation cases. Three of them have supervision terms that ended before January 1, 2026 (their "Supervision End Date" in the case details is in the past). The Probation Officer must:

1. Review all 6 cases to identify the 3 with expired supervision terms
2. For each expired case:
   - Change the case Status to **`Closed`**
   - Add a case note containing: `CASE CLOSED: Supervision term completed. Final compliance verified. Case administratively closed per SOP-PO-12.`
3. Leave the 3 active cases (supervision end date in 2026 or later) unchanged.

## Starting State

6 complaint records pre-created via setup_task.sh:

### Expired Cases (3) — supervision ended, must be closed:
- **Probation Supervision: Alicia J. Drummond** — Supervision End Date: 2025-10-31
- **Probation Supervision: Trevor B. Okonkwo** — Supervision End Date: 2025-11-15
- **Probation Supervision: Sandra L. Petrov** — Supervision End Date: 2025-08-01

### Active Cases (3) — supervision ongoing, must NOT be modified:
- **Probation Supervision: Bruno M. Reinholt** — Supervision End Date: 2026-06-30
- **Probation Supervision: Yuki T. Nakashima** — Supervision End Date: 2026-09-15
- **Probation Supervision: Celeste A. Fontenot** — Supervision End Date: 2026-12-01

## Difficulty

**VERY HARD**: The task does not identify which cases are expired. The agent must:
- Navigate to the Complaints module and open each of the 6 cases
- Read the Supervision End Date from the case details
- Determine which dates are before January 1, 2026
- Close each expired case (change status + add note) — 6 total actions across 3 cases
- Avoid modifying the 3 active cases

## Verification Criteria

1. **Expired cases closed (40 pts)**: All 3 expired cases have cm_complaint_status = 'Closed' (partial credit: 13 pts per case)
2. **Active cases untouched (20 pts)**: None of the 3 active cases have status = 'Closed'
3. **Closure notes added (40 pts)**: At least 3 notes containing 'CASE CLOSED' and 'SOP-PO-12' linked to expired case IDs

Pass threshold: 70/100

## Schema Reference

```sql
-- Check complaint status
SELECT cm_complaint_id, cm_complaint_title, cm_complaint_status
FROM acm_complaint
WHERE cm_complaint_id IN (...);

-- Check notes
SELECT cm_note_id, cm_note_text, cm_parent_object_id
FROM acm_note
WHERE cm_parent_object_type = 'COMPLAINT'
AND cm_note_text ILIKE '%CASE CLOSED%';
```
