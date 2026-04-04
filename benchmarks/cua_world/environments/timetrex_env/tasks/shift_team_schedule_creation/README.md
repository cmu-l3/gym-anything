# Shift Team Schedule Creation

## Overview

A production facility runs two rotating shift teams with alternating day/evening patterns. As a First-Line Supervisor, you must build the two-week schedule in TimeTrex before it can be published to staff. Missing or wrong schedule entries mean employees don't know when to show up and automated time-tracking triggers fail.

## Goal

Create 12 schedule entries in TimeTrex covering two teams with different shift windows across 6 days:

**Team A — Morning Shift (06:00–14:00):** Emma Johnson (EM-SC001) and Ryan Garcia (EM-SC002), working Mon/Wed/Fri: March 9, 11, 13, 2026.

**Team B — Afternoon Shift (14:00–22:00):** Sarah Mitchell (EM-SC003) and David Kim (EM-SC004), working Tue/Thu/Sat: March 10, 12, 14, 2026.

Total: 4 employees × 3 days = **12 schedule entries**.

## Success Criteria

1. Each of the 12 expected entries exists in the `schedule` table (not deleted) for the correct employee and date.
2. Each Team A entry has start_time 06:00 and end_time 14:00 (±0 tolerance on HH:MM).
3. Each Team B entry has start_time 14:00 and end_time 22:00 (±0 tolerance on HH:MM).

Scoring: 6 pts per entry found + 2 pts per entry with correct times = max 96, +4 bonus if all 12 are time-correct = 100.

## Verification Strategy

`export_result.sh` queries `schedule JOIN users` for each of the 12 (employee_number, date_stamp) pairs and records found/start_ok/end_ok per entry. The verifier counts found entries and time-correct entries separately.

Anti-gaming: Initial schedule count for these employees and dates is recorded at setup time. If initial_count ≥ 12, the verifier returns score=0.

## Schema Reference

```sql
SELECT s.start_time::text, s.end_time::text
FROM schedule s
JOIN users u ON s.user_id = u.id
WHERE u.employee_number = 'EM-SC001'
  AND s.date_stamp = '2026-03-09'
  AND s.deleted = 0;
-- start_time / end_time are TIME columns stored as 'HH:MM:SS'
-- date_stamp is a DATE column stored as 'YYYY-MM-DD'
```

## Edge Cases

- TimeTrex may store 06:00:00 as start_time; the verifier compares only the first 5 chars (HH:MM).
- The agent may use the Schedule Planner or individual schedule creation; either approach is accepted.
- Saturday (2026-03-14) may require changing the weekly schedule template; it is a valid work day.

## Starting State (seeded by setup_task.sh)

Four employees are inserted with no schedule entries. Any pre-existing schedules on the target dates are cleared.

| Employee | Emp # | Team | Days |
|----------|-------|------|------|
| Emma Johnson | EM-SC001 | A | Mon/Wed/Fri |
| Ryan Garcia | EM-SC002 | A | Mon/Wed/Fri |
| Sarah Mitchell | EM-SC003 | B | Tue/Thu/Sat |
| David Kim | EM-SC004 | B | Tue/Thu/Sat |
