# Task: Probation Caseload Triage

## Domain Context

Probation Officers and Correctional Treatment Specialists are the primary users of ArkCase-style case management software. Their workflow involves tracking offender compliance, recording case notes, managing supervision levels, and scheduling interactions. This task simulates a real monthly caseload review workflow.

## Goal

Seven complaint records exist representing probationers. Three of them are non-compliant (their case details show a "Last Contact" date before December 1, 2025, meaning they have missed their mandatory 30-day check-in). The agent must:

1. Review all 7 cases and identify the 3 non-compliant ones (discovery required - agent is NOT told which)
2. For each non-compliant case:
   - Change priority to 'High' (from current 'Low')
   - Add a specific case note
   - Create a specific task

The 4 compliant cases must NOT be modified.

## Starting State

7 complaint records are pre-created via setup_task.sh:

### Non-Compliant Cases (3) — these must be identified and modified:
- Donatello Williams - Probation Supervision: Last Contact: 2025-09-14 (173 days before task date)
- Rosa Gutierrez - Probation Supervision: Last Contact: 2025-10-02 (148 days before task date)
- Marcus Reed - Probation Supervision: Last Contact: 2025-08-30 (181 days before task date)

### Compliant Cases (4) — must NOT be modified:
- Kevin Osei - Probation Supervision: Last Contact: 2026-01-15 (within 30 days)
- Priya Nair - Probation Supervision: Last Contact: 2026-01-22 (within 30 days)
- Jamal Foster - Probation Supervision: Last Contact: 2026-02-05 (within 30 days)
- Tanya Belobrov - Probation Supervision: Last Contact: 2026-02-18 (within 30 days)

## Difficulty

**VERY HARD**: The task description does not identify which cases are non-compliant. The agent must:
- Navigate to the Complaints module
- Open each of the 7 cases to read the details
- Make a judgment call based on the Last Contact date
- Perform 3 separate actions on each of 3 cases (9 total actions)
- Avoid modifying compliant cases

## Verification Criteria

**Verification is done via PostgreSQL queries to arkcase-rdbms-0 pod:**

1. **Priority escalation (30 pts)**: The 3 non-compliant case IDs each have cm_complaint_priority = 'High' (changed from 'Low')
2. **Compliant cases untouched (20 pts)**: The 4 compliant case IDs still have their original priorities (not changed to High)
3. **Notes added (25 pts)**: At least 3 notes in acm_note with cm_parent_object_type='COMPLAINT' containing 'NON-COMPLIANCE FLAGGED' and linked to non-compliant case IDs
4. **Tasks created (25 pts)**: At least 3 tasks in act_ru_task with name_ = 'Schedule immediate office report'

Pass threshold: 70/100

## Schema Reference

```sql
-- Check complaint status
SELECT cm_complaint_id, cm_complaint_title, cm_complaint_priority
FROM acm_complaint
WHERE cm_complaint_id IN (...);

-- Check notes
SELECT cm_note_id, cm_note_text, cm_parent_object_id, cm_parent_object_type
FROM acm_note
WHERE cm_parent_object_type = 'COMPLAINT'
AND cm_note_text ILIKE '%NON-COMPLIANCE FLAGGED%';

-- Check tasks
SELECT id_, name_, assignee_, priority_
FROM act_ru_task
WHERE name_ = 'Schedule immediate office report';
```
