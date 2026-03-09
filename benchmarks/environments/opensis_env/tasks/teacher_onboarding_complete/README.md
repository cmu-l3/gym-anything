# Task: Teacher Onboarding Complete

## Overview

This task simulates an HR Manager / Principal (Education Administrator, SOC 11-9033.00) completing
the full onboarding process for a new foreign language teacher in OpenSIS. The task requires three
distinct OpenSIS modules: Staff management, Course catalog, and Grade entry — all linked in a
realistic "new hire + new course + first assessment" workflow.

## Goal

Complete full onboarding for new teacher Jennifer Torres at Riverside High School:
1. **Add staff member** — Jennifer Torres as Teacher
2. **Create course** — Spanish III (SPAN301)
3. **Enter placement test scores** — for two pre-seeded 10th-grade students

## New Staff Member

| Field | Value |
|-------|-------|
| First name | Jennifer |
| Last name | Torres |
| Email | jtorres@riverside.edu |
| Role/Profile | Teacher |

## New Course

| Field | Value |
|-------|-------|
| Course name | Spanish III |
| Course code | SPAN301 |
| Subject area | Foreign Language |
| Grade level | 10 |
| Credits | 1.0 |

## Grade Entries (Assignment: Placement Test)

| Student | Grade |
|---------|-------|
| Carlos Mendez | 82 |
| Ana Nguyen | 89 |

## Success Criteria

Staff record, course record, and both placement test grade records must all be present.

## Scoring

| Criterion | Points |
|-----------|--------|
| A: Jennifer Torres staff record correct | 25 |
| B: SPAN301 course created correctly | 25 |
| C: Both Placement Test grade records found in SPAN301 | 25 |
| D: Grade values correct (82, 89) | 25 |
| **Total** | **100** |

**Pass threshold**: 60 points

## Verification Strategy

Queries `staff` for Jennifer Torres, `courses` for SPAN301, and `grades` scoped to SPAN301 (course_id)
with assignment='Placement Test' for students named Carlos and Ana.

**Wrong-target gate**: If Placement Test grades exist for unexpected students in SPAN301, score = 0.

## Database Schema

```sql
staff(staff_id, current_school_id, title, first_name, last_name, email, profile, profile_id)
courses(course_id, course_name, course_code, subject_area, grade_level, credits)
grades(grade_id, student_id, course_id, assignment_name, grade_value)
students(student_id, first_name, last_name, date_of_birth, gender, grade_level)
```

## Setup

`setup_task.sh` seeds Carlos Mendez (Gr10, M, DOB: 2007-02-15) and Ana Nguyen (Gr10, F, DOB: 2007-06-21).
Removes any pre-existing Jennifer Torres staff and SPAN301 course. Records baseline timestamp and counts.

## Notes

- Login: admin / Admin@123
- Carlos Mendez and Ana Nguyen are pre-seeded; agent does NOT need to create them
- The agent must create Jennifer Torres (staff), SPAN301 (course), then enter grades
- No UI navigation hints are provided
