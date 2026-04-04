# Task: Advanced Workforce Analytics with Oracle SQL

## Overview

A health informatics company's workforce analytics team needs 4 business intelligence answers extracted from the Oracle HR database. This requires advanced SQL techniques: window functions, CTEs, multi-table joins, set operations (UNION ALL), and aggregation across the EMPLOYEES, JOB_HISTORY, JOBS, DEPARTMENTS, and LOCATIONS tables.

## Goal

Using Oracle analytical SQL, answer all 4 questions and save a clearly labeled report to `/home/ga/Desktop/workforce_analytics_report.txt`. Each answer must be labeled with Q1, Q2, Q3, Q4.

## The 4 Questions

**Q1 — Highest Average Salary City**
Which city has the highest average employee salary across all current employees? Report the city name and the average salary rounded to 2 decimal places.

**Q2 — Widest Manager Span**
Which manager currently has the most direct reports (employees who have that manager as their MANAGER_ID)? Report the manager's full name (first_name || ' ' || last_name) and the direct report count.

**Q3 — Average Salary Increase on Job Change**
For employees who appear in JOB_HISTORY (meaning they changed roles at some point), what is the average percentage increase in minimum job salary from their historical role to their current role? Report the percentage rounded to 2 decimal places.

**Q4 — Most Mobile Job Title**
Which job title has been held by the most distinct employees, counting both current employees (EMPLOYEES.JOB_ID) and historical records (JOB_HISTORY.JOB_ID) via UNION ALL? Report the job title and the count of distinct employees.

## Environment

- **Database**: Oracle XE 21c (container: `oracle-xe`)
- **Schema**: HR (user: `hr`, password: `hr123`)
- **PDB**: XEPDB1 (port 1521)
- **Client**: DBeaver CE (pre-configured)

## Key Tables

| Table | Rows | Key columns |
|-------|------|-------------|
| EMPLOYEES | 107 | EMPLOYEE_ID, FIRST_NAME, LAST_NAME, SALARY, JOB_ID, DEPARTMENT_ID, MANAGER_ID |
| JOB_HISTORY | 10 | EMPLOYEE_ID, START_DATE, END_DATE, JOB_ID, DEPARTMENT_ID |
| JOBS | 19 | JOB_ID, JOB_TITLE, MIN_SALARY, MAX_SALARY |
| DEPARTMENTS | 27 | DEPARTMENT_ID, DEPARTMENT_NAME, LOCATION_ID |
| LOCATIONS | 23 | LOCATION_ID, CITY, STATE_PROVINCE, COUNTRY_ID |

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Report file exists on Desktop | 10 |
| File has ≥10 non-blank lines | 5 |
| Q1 label present | 3 |
| Q2 label present | 3 |
| Q3 label present | 3 |
| Q4 label present | 3 |
| Q1 correct city | 15 |
| Q1 salary within 5% of correct | 5 (bonus) |
| Q2 correct manager name | 15 |
| Q2 report count within ±2 | 5 (bonus) |
| Q3 percentage found | 10 |
| Q3 value close to expected | 5 (bonus) |
| Q4 correct job title | 15 |
| Report structure (all labels + numbers) | 8 |
| **Total (base)** | **90** |
| **Total (with bonuses)** | **~105** |

Pass threshold: 50 points

## Verification Strategy

The verifier:
1. Reads the exported result JSON (which includes the report content and extracted values)
2. Checks for Q1-Q4 labels in the file
3. Scans for known HR city names, manager names, and job titles
4. Extracts numeric values near each question label
5. Compares extracted values to pre-computed ground truth stored in `/tmp/workforce_analytics_ground_truth.json`

## Notes

- The report file format is flexible — plain text, formatted tables, or simple key-value pairs all work
- Oracle analytical functions like RANK(), DENSE_RANK(), OVER(PARTITION BY ...) are useful here
- For Q4, `UNION ALL` (not `UNION`) preserves duplicates before counting distinct employees
- All joins needed: EMPLOYEES → DEPARTMENTS → LOCATIONS for Q1; self-join EMPLOYEES for Q2
- Example spool command in DBeaver: File → Export Results → CSV/Text
