# Task: Transfer Student Intake

## Overview

This task simulates a school registrar completing a full transfer student intake in OpenSIS.
The registrar role (Education Administrators, SOC 11-9033.00) is the primary occupation for
Student Information Systems — they manage enrollment, course registration, and academic records
as core daily workflows.

## Goal

Complete the full intake for a mid-year transfer student by performing three linked operations
in OpenSIS that span three distinct application modules:

1. **Student enrollment** — Create the new student record
2. **Course management** — Create three courses in the course catalog
3. **Grade entry** — Record the student's transfer grades across those courses

## Target

- **Student**: Zara Hoffman
  - Gender: Female
  - Date of Birth: August 22, 2007
  - Grade Level: 11

## Required Courses

| Course Name | Code | Subject | Grade Level | Credits |
|-------------|------|---------|-------------|---------|
| Advanced Chemistry | CHEM301 | Science | 11 | 1.0 |
| AP English Language | ENG401 | English | 11 | 1.0 |
| US History | HIST201 | Social Studies | 11 | 0.5 |

## Required Grades

Assignment name: **Transfer Final Grade**

| Course | Grade |
|--------|-------|
| CHEM301 | 91 |
| ENG401 | 88 |
| HIST201 | 79 |

## Success Criteria

All three of the following must be completed:
1. Zara Hoffman student record exists with correct demographics
2. All three courses exist in the catalog with correct fields
3. All three grade records exist linked to Zara Hoffman with correct values

## Scoring

| Criterion | Points |
|-----------|--------|
| A: Student record created correctly | 20 |
| B: All three courses created correctly | 25 |
| C: All three grade records linked to Zara | 35 |
| D: Grade values correct (91, 88, 79) | 20 |
| **Total** | **100** |

**Pass threshold**: 60 points

## Verification Strategy

The verifier queries the database directly via `exec_in_env`:
- Checks `students` table for Zara Hoffman (first_name, last_name, date_of_birth, gender, grade_level)
- Checks `courses` table for CHEM301, ENG401, HIST201 (code, subject_area, grade_level, credits)
- Checks `grades` table joined to both student and course for the three grade records
- Validates grade values within ±1.0 of expected

**Wrong-target gate**: If grades with assignment='Transfer Final Grade' are found for other students
in these courses, score = 0 immediately.

## Database Schema

```sql
students(student_id, first_name, last_name, date_of_birth, gender, grade_level)
courses(course_id, course_name, course_code, subject_area, grade_level, credits)
grades(grade_id, student_id, course_id, assignment_name, grade_value)
```

## Setup

`setup_task.sh` cleans any pre-existing Zara Hoffman records and pre-existing CHEM301/ENG401/HIST201
courses to ensure a clean starting state. Records a baseline timestamp and initial counts.

## Notes

- Login: admin / Admin@123
- The agent must independently navigate the Students, Courses, and Grades sections of OpenSIS
- No UI navigation hints are provided — the agent must discover the correct forms
