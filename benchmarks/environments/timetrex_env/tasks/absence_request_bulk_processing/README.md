# Absence Request Bulk Processing

## Overview

At the end of a busy week, five absence requests have accumulated in the queue. Company policy dictates specific approval/denial rules based on leave type and duration. As a First-Line Supervisor, you must process all five before the close of business — unapproved requests block payroll calculation and leave accrual.

## Goal

Review all five pending absence requests in TimeTrex and apply the policy:
- Sick leave → always approve
- Vacation ≤ 2 days → approve
- Vacation ≥ 3 days → deny

All five requests must be actioned (no request left as Pending = status_id 10).

## Policy Application

| Employee | Emp # | Type | Duration | Expected Action |
|----------|-------|------|----------|----------------|
| Lisa Anderson | EM-RQ001 | Sick | 1 day | **Approve** |
| Tom Peterson | EM-RQ002 | Vacation | 3 days | **Deny** |
| Olivia Martinez | EM-RQ003 | Vacation | 2 days | **Approve** |
| Kevin Chang | EM-RQ004 | Vacation | 5 days | **Deny** |
| Sandra Brown | EM-RQ005 | Sick | 1 day | **Approve** |

## Success Criteria

Each of the 5 requests is worth 20 points (total = 100):
1. Lisa Anderson's request status = Approved (status_id = 20)
2. Tom Peterson's request status = Denied (status_id = 30)
3. Olivia Martinez's request status = Approved (status_id = 20)
4. Kevin Chang's request status = Denied (status_id = 30)
5. Sandra Brown's request status = Approved (status_id = 20)

A request left Pending (status_id = 10) scores 0. A request actioned with the wrong decision also scores 0.

## Verification Strategy

`export_result.sh` queries `request JOIN users` by employee number, looking for the most recent request row sorted by `id DESC`. The `status_id` value is compared against the expected outcome.

## Schema Reference

```sql
-- status_id values: 10 = Pending, 20 = Approved, 30 = Denied
SELECT r.status_id
FROM request r
JOIN users u ON r.user_id = u.id
WHERE u.employee_number = 'EM-RQ001'
  AND u.deleted = 0 AND r.deleted = 0
ORDER BY r.id DESC LIMIT 1;

-- type_id references absence_policy.id
-- Vacation type: WHERE LOWER(name) LIKE '%vacation%'
-- Sick type: WHERE LOWER(name) LIKE '%sick%'
```

## Edge Cases

- The Sick policy ID and Vacation policy ID are looked up from `absence_policy` at setup time. Fallback IDs are 10 (Vacation) and 20 (Sick) if the demo data uses different names.
- The agent may need to navigate to a "My Requests" or "Pending Requests" queue; the exact UI path is not specified.
- Multiple pending requests on the same date (Tom Peterson and Lisa Anderson both on 2026-03-16) should not confuse the verifier because it keys on employee number.

## Starting State (seeded by setup_task.sh)

All five requests are inserted with status_id = 10 (Pending). All employees are active (status_id = 10).
