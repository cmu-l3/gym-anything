# Task: Hearing Schedule Conflict Resolution

## Domain Context

Administrative Law Judges (ALJs) use ArkCase to manage their docket of administrative hearings. A critical daily workflow is docket management: reviewing pending cases, identifying scheduling problems, and adding disposition notes. When a case has been pending beyond its regulatory deadline, the ALJ must flag it with a continuance note and escalate its priority so staff can reschedule. This task simulates real ALJ docket triage.

## Goal

Five complaint records are in the system representing pending administrative hearings. Three of them are **overdue**: their hearing dates (encoded in case details as "Hearing Date") are more than 60 days in the past (before December 30, 2025). The ALJ must:

1. Review all 5 cases to identify the 3 overdue ones
2. For each overdue case:
   - Change the case Priority to **'High'**
   - Add a case note containing exactly: `CONTINUANCE REQUIRED: Hearing date exceeded 60-day regulatory deadline. Docket rescheduling mandatory per ALJ-Admin Rule 4.2.`
   - Set the case **Status** to `'In Progress'` (if not already)
3. The 2 non-overdue cases must NOT be modified.

## Starting State

5 complaint records pre-created via setup_task.sh:

### Overdue Cases (3) — must be identified and modified:
- **ALJ Docket #DR-2025-0841** — Respondent: Hargrove Industries LLC, Hearing Date: 2025-10-15 (135 days overdue as of task date)
- **ALJ Docket #DR-2025-0756** — Respondent: Castellan Medical Group, Hearing Date: 2025-11-03 (117 days overdue)
- **ALJ Docket #DR-2025-0903** — Respondent: Meridian Property Trust, Hearing Date: 2025-09-28 (152 days overdue)

### Current Cases (2) — must NOT be modified:
- **ALJ Docket #DR-2026-0112** — Respondent: Thornfield Education Partners, Hearing Date: 2026-02-10 (within deadline)
- **ALJ Docket #DR-2026-0134** — Respondent: Verity Healthcare Systems, Hearing Date: 2026-03-05 (future)

## Difficulty

**VERY HARD**: The task description does not identify which dockets are overdue. The agent must:
- Navigate to the Complaints module and open each of the 5 cases
- Parse the hearing date from the case details text
- Calculate which dates exceed the 60-day threshold (before Dec 30, 2025)
- Perform 3 separate actions on each of 3 overdue cases (9 total actions)
- Avoid modifying the 2 current cases

## Verification Criteria

**Verification via PostgreSQL queries to arkcase-rdbms-0 pod:**

1. **Priority escalation (30 pts)**: The 3 overdue case IDs each have cm_complaint_priority = 'High'
2. **Current cases untouched (20 pts)**: The 2 non-overdue case IDs have NOT been changed to 'High'
3. **Continuance notes added (30 pts)**: At least 3 notes in acm_note containing 'CONTINUANCE REQUIRED' linked to overdue case IDs
4. **Status updated (20 pts)**: At least 2 of 3 overdue cases have cm_complaint_status = 'In Progress'

Pass threshold: 70/100

## Schema Reference

```sql
-- Check complaint priorities and status
SELECT cm_complaint_id, cm_complaint_title, cm_complaint_priority, cm_complaint_status
FROM acm_complaint
WHERE cm_complaint_id IN (...);

-- Check notes
SELECT cm_note_id, cm_note_text, cm_parent_object_id
FROM acm_note
WHERE cm_parent_object_type = 'COMPLAINT'
AND cm_note_text ILIKE '%CONTINUANCE REQUIRED%';
```
