# Comprehensive Employee Onboarding

## Overview

A new production worker, Robert Nakamura, has been added to TimeTrex as a user record but has not yet been configured for payroll or scheduling. As an HR Manager / First-Line Supervisor, you must complete his full onboarding setup: entering compensation information and building two weeks of work schedules. This multi-feature task requires using three separate modules of TimeTrex.

## Goal

For employee Robert Nakamura (EM-ON001), complete all three onboarding steps:

1. **Wage setup**: Set hourly wage to $19.50, effective date 2026-02-01.
2. **Schedule Week 1**: Create Monday–Friday schedule entries for March 9–13, 2026, from 07:00–15:00 each day.
3. **Schedule Week 2**: Create Monday–Friday schedule entries for March 16–20, 2026, from 07:00–15:00 each day.

Robert currently has no wage record and no schedule entries. All three steps must be completed for full credit.

## Success Criteria

Each subtask is independently scored:

1. **(30 pts)** Wage record exists with wage = $19.50 (±$0.005) and effective_date = 2026-02-01. Partial: 20 pts if wage is correct but effective date differs.
2. **(35 pts)** All 5 schedule entries for Week 1 (Mar 9–13) exist with start_time = 07:00 and end_time = 15:00. Partial: 4 pts per day found (out of 5); 20 pts if all 5 found but wrong times.
3. **(35 pts)** All 5 schedule entries for Week 2 (Mar 16–20) exist with start_time = 07:00 and end_time = 15:00. Partial: 4 pts per day found; 20 pts if all 5 found but wrong times.

Pass threshold: 60 points (completing any 2 of the 3 subtasks fully).

## Verification Strategy

`export_result.sh`:
- Queries `user_wage JOIN users` for EM-ON001, takes the most recent wage by effective_date DESC.
- For each of the 10 schedule dates, queries `schedule JOIN users` checking start_time and end_time.

## Schema Reference

```sql
-- Wage
SELECT wage, effective_date::text
FROM user_wage uw JOIN users u ON uw.user_id = u.id
WHERE u.employee_number = 'EM-ON001' AND u.deleted = 0 AND uw.deleted = 0
ORDER BY uw.effective_date DESC LIMIT 1;

-- Schedule (one date example)
SELECT start_time::text, end_time::text
FROM schedule s JOIN users u ON s.user_id = u.id
WHERE u.employee_number = 'EM-ON001'
  AND s.date_stamp = '2026-03-09' AND s.deleted = 0
ORDER BY s.id DESC LIMIT 1;
```

## Edge Cases

- The agent must locate Robert Nakamura in the Employee list — his user_name is `robert.nakamura.on001`.
- Wage entry is typically under Employee > Edit > Wage tab or via a separate Wage module.
- Schedule creation for 10 days may be done day-by-day or via a schedule template/copy function.
- The agent needs to discover that 07:00–15:00 maps to a 8-hour shift; the verifier checks HH:MM (first 5 chars of the time column).

## Starting State (seeded by setup_task.sh)

Robert Nakamura (EM-ON001) is inserted as an active employee with no wage records and no schedule entries.
