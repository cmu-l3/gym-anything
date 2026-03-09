# Task: Course and Teacher Grades Setup

## Overview

This task simulates a school principal (Education Administrator, SOC 11-9033.00) setting up a new
science department at the start of a semester. The principal must add a new teacher to the staff,
create their course, and enter initial lab grades for enrolled students — three distinct workflows
in OpenSIS that must be completed in dependency order.

## Goal

Complete department setup by performing three linked operations:
1. **Staff onboarding** — Add Dr. Evelyn Park as a Teacher
2. **Course creation** — Create Advanced Biology (BIO401) in the course catalog
3. **Grade entry** — Enter Lab Practical grades for three pre-seeded 12th-grade students

## New Staff Member

| Field | Value |
|-------|-------|
| Title | Dr. |
| First name | Evelyn |
| Last name | Park |
| Email | epark@school.edu |
| Role/Profile | Teacher |

## New Course

| Field | Value |
|-------|-------|
| Course name | Advanced Biology |
| Course code | BIO401 |
| Subject area | Science |
| Grade level | 12 |
| Credits | 1.0 |

## Grade Entries (Assignment: Lab Practical)

| Student | Grade |
|---------|-------|
| Sophie Walsh | 94 |
| Kevin O'Brien | 87 |
| Maya Rodriguez | 91 |

## Success Criteria

All three must be completed: staff record, course record, and grade records.

## Scoring

| Criterion | Points |
|-----------|--------|
| A: Dr. Evelyn Park staff record correct | 25 |
| B: BIO401 course created correctly | 25 |
| C: All three Lab Practical grade records found | 25 |
| D: Grade values correct (94, 87, 91) | 25 |
| **Total** | **100** |

**Pass threshold**: 60 points

## Verification Strategy

Queries `staff`, `courses`, and `grades` tables. The grade check is scoped to BIO401 (by course_id)
and to the three target first names ('Sophie', 'Kevin', 'Maya').

**Wrong-target gate**: If Lab Practical grades exist for unexpected students in BIO401, score = 0.

## Database Schema

```sql
staff(staff_id, current_school_id, title, first_name, last_name, email, profile, profile_id)
courses(course_id, course_name, course_code, subject_area, grade_level, credits)
grades(grade_id, student_id, course_id, assignment_name, grade_value)
students(student_id, first_name, last_name, date_of_birth, gender, grade_level)
```

## Setup

`setup_task.sh` seeds Sophie Walsh, Kevin O'Brien, and Maya Rodriguez as Grade 12 students.
It also removes any pre-existing Dr. Evelyn Park staff record and BIO401 course to ensure clean state.
Records baseline timestamp and counts.

## Notes

- Login: admin / Admin@123
- Sophie Walsh, Kevin O'Brien, Maya Rodriguez are pre-seeded (the agent does NOT need to create them)
- The agent must create Dr. Park and BIO401, then enter grades for the pre-seeded students
- No UI navigation hints are provided
