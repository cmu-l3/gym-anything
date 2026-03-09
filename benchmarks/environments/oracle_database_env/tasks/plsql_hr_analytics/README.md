# Task: PL/SQL HR Analytics Package Development

## Overview

An IT manager at a health informatics company needs a reusable Oracle PL/SQL analytics package for the HR schema. The company's database team must deliver a package that supports salary benchmarking, compensation matrix reporting, and organizational hierarchy queries — all in a single deployable unit.

## Goal

Create a PL/SQL package named `HR_ANALYTICS` in the Oracle HR schema containing three components:

1. **Function `DEPT_SALARY_STATS(p_dept_id IN NUMBER) RETURN VARCHAR2`**
   Returns a pipe-formatted string: `AVG:nnn|MIN:nnn|MAX:nnn`
   - Uses the `EMPLOYEES` table to compute statistics for the given department
   - Values should be rounded to nearest integer

2. **Procedure `BUILD_COMPENSATION_MATRIX`**
   Creates (or replaces) a table named `COMPENSATION_MATRIX` containing one row per employee with:
   - `EMPLOYEE_ID` — numeric
   - `FULL_NAME` — first_name || ' ' || last_name
   - `JOB_TITLE` — from JOBS table
   - `CURRENT_SALARY` — from EMPLOYEES
   - `DEPT_AVG_SALARY` — average salary for the employee's department
   - `SALARY_DEVIATION_PCT` — ((current - dept_avg) / dept_avg) * 100, rounded to 2dp
   - `GRADE_LEVEL` — single character A–E from JOB_GRADES based on salary bracket

3. **Function `REPORTING_CHAIN(p_emp_id IN NUMBER) RETURN VARCHAR2`**
   Returns a pipe-delimited string of full names from the employee up to the top of the hierarchy.
   Example: `Neena Kochhar|Steven King`

After building the package, run `BUILD_COMPENSATION_MATRIX` and export the result of:
```sql
SELECT * FROM compensation_matrix ORDER BY employee_id;
```
to `/home/ga/Desktop/compensation_matrix.txt`.

## Environment

- **Database**: Oracle XE 21c (container: `oracle-xe`)
- **Schema**: HR (user: `hr`, password: `hr123`)
- **PDB**: XEPDB1 (port 1521)
- **Client**: DBeaver CE (pre-configured connection)
- **Relevant tables**: EMPLOYEES, JOBS, JOB_GRADES, DEPARTMENTS

## Success Criteria

| Criterion | Points |
|-----------|--------|
| HR_ANALYTICS package exists and is VALID | 10 |
| DEPT_SALARY_STATS function exists | 10 |
| DEPT_SALARY_STATS returns correct AVG:n\|MIN:n\|MAX:n format | 10 |
| BUILD_COMPENSATION_MATRIX procedure exists | 5 |
| COMPENSATION_MATRIX table created with ≥100 rows | 10 |
| All 7 required columns present in table | 10 |
| GRADE_LEVEL values are valid (A–E only) | 5 |
| REPORTING_CHAIN function exists | 5 |
| REPORTING_CHAIN returns pipe-delimited chain | 10 |
| compensation_matrix.txt on Desktop with ≥100 lines | 10 |
| File contains structured data | 5 |
| **Total** | **100** |

Pass threshold: 60 points

## Key Reference Data

### JOB_GRADES table
| Grade | Lowest Sal | Highest Sal |
|-------|-----------|-------------|
| A | 1,000 | 2,999 |
| B | 2,000 | 4,999 |
| C | 4,000 | 7,999 |
| D | 7,000 | 14,999 |
| E | 12,000 | 24,999 |

### Sample department IDs
- Department 90 (Executive): 3 employees, very high salaries
- Department 60 (IT): 5 employees
- Department 100 (Finance): 6 employees

## Verification Strategy

The verifier:
1. Calls `HR_ANALYTICS.DEPT_SALARY_STATS(90)` and checks the output format
2. Calls `HR_ANALYTICS.REPORTING_CHAIN(101)` (Neena Kochhar → Steven King)
3. Queries `USER_OBJECTS` to confirm package status = VALID
4. Queries `COMPENSATION_MATRIX` table for row count, column names, grade values
5. Checks `/home/ga/Desktop/compensation_matrix.txt` size and content

## Notes

- The `HR_ANALYTICS` package slot is cleared before the task starts
- The `COMPENSATION_MATRIX` table slot is cleared before the task starts
- Use DBeaver's SQL editor to write and execute PL/SQL
- You can use `CREATE OR REPLACE PACKAGE` and `CREATE OR REPLACE PACKAGE BODY`
