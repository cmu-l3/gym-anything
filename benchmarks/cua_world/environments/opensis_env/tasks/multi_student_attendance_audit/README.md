# Task: Multi-Student Attendance Audit

## Overview

This task simulates an attendance coordinator performing a retroactive attendance correction in
OpenSIS. Attendance Coordinators / Education Administrators (SOC 11-9033.00) regularly need to
correct missing or erroneous attendance entries — a core function of any school SIS.

## Goal

Enter the missing attendance records for three 10th-grade students for the date **November 4, 2024**.
The records were not entered on that date and must now be added.

## Target Students (pre-seeded in setup)

| Name | Grade | DOB | Required Status |
|------|-------|-----|-----------------|
| Miguel Santos | 10 | 2006-05-12 | Present |
| Aisha Patel | 10 | 2006-08-29 | Absent |
| Dmitri Volkov | 10 | 2006-03-17 | Tardy |

## Success Criteria

All three attendance records for 2024-11-04 must be entered with the correct status values.

## Scoring

| Criterion | Points |
|-----------|--------|
| A: Miguel Santos — Present on 2024-11-04 | 33 |
| B: Aisha Patel — Absent on 2024-11-04 | 33 |
| C: Dmitri Volkov — Tardy on 2024-11-04 | 34 |
| **Total** | **100** |

**Pass threshold**: 60 points

## Verification Strategy

The verifier queries `attendance` joined with `students` for each target student on 2024-11-04.
Status values accepted: Present/P/1, Absent/A/0, Tardy/T/Late (case-insensitive variants).

**Wrong-target gate**: If more than 5 unexpected students have attendance recorded on 2024-11-04,
score = 0 (agent modified unrelated records).

## Database Schema

```sql
students(student_id, first_name, last_name, date_of_birth, gender, grade_level)
attendance(attendance_id, student_id, attendance_date, status)
```

## Setup

`setup_task.sh` seeds Miguel Santos, Aisha Patel, and Dmitri Volkov into the `students` table
(removing any previous copies first). No pre-existing attendance on 2024-11-04 is seeded.
Records a baseline timestamp and initial attendance count.

## Notes

- Login: admin / Admin@123
- The three students are pre-loaded; the agent must find them in OpenSIS and enter their attendance
- The date 2024-11-04 must be used exactly
- No UI navigation hints are provided
