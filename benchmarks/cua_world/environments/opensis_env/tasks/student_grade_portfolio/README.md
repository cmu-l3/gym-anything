# Task: Student Grade Portfolio

## Overview

This task simulates a school counselor (Education Administrator, SOC 11-9033.00) building out the
academic record for a college-bound 11th-grade student. The counselor must create four courses in
the OpenSIS catalog and then enter the student's semester final grades across all four — requiring
coordination across two distinct application modules for a single target student.

## Goal

Build the academic portfolio for **Brandon Lee** (Grade 11, DOB: September 30, 2006) by:
1. Creating four courses in the OpenSIS catalog
2. Entering his Semester Final Grades in each course

## Target Student (pre-seeded)

| Field | Value |
|-------|-------|
| First name | Brandon |
| Last name | Lee |
| DOB | 2006-09-30 |
| Gender | M |
| Grade Level | 11 |

## Required Courses

| Course Name | Code | Subject | Grade Level | Credits |
|-------------|------|---------|-------------|---------|
| AP Statistics | STAT101 | Math | 11 | 1.0 |
| Creative Writing | WRIT101 | English | 11 | 1.0 |
| Civics | CIVIC101 | Social Studies | 11 | 0.5 |
| Photography | PHOTO101 | Arts | 11 | 0.5 |

## Required Grades (Assignment: Semester Final Grade)

| Course | Grade |
|--------|-------|
| STAT101 | 85 |
| WRIT101 | 92 |
| CIVIC101 | 78 |
| PHOTO101 | 96 |

## Success Criteria

All four courses must be created and all four grade records must be entered for Brandon Lee.

## Scoring

| Criterion | Points |
|-----------|--------|
| A: Brandon Lee student record found (pre-seeded sanity) | 10 |
| B: All four courses exist with correct attributes | 25 |
| C: All four grade records linked to Brandon Lee | 40 |
| D: All four grade values correct | 25 |
| **Total** | **100** |

**Pass threshold**: 60 points

## Verification Strategy

Queries `students` for Brandon Lee, `courses` for STAT101/WRIT101/CIVIC101/PHOTO101, and `grades`
joined to both — scoped to Brandon's student_id and the four course codes with assignment='Semester Final Grade'.

**Wrong-target gate**: If 'Semester Final Grade' entries exist for other students in these four courses,
score = 0.

## Database Schema

```sql
students(student_id, first_name, last_name, date_of_birth, gender, grade_level)
courses(course_id, course_name, course_code, subject_area, grade_level, credits)
grades(grade_id, student_id, course_id, assignment_name, grade_value)
```

## Setup

`setup_task.sh` seeds Brandon Lee into the `students` table and cleans up any pre-existing
STAT101/WRIT101/CIVIC101/PHOTO101 courses and prior 'Semester Final Grade' entries for Brandon.
Records baseline timestamp and counts.

## Notes

- Login: admin / Admin@123
- Brandon Lee is pre-seeded; the agent only needs to create courses and enter grades
- Creating four courses and linking four grades in OpenSIS requires navigating multiple UI sections
- No UI navigation hints are provided
