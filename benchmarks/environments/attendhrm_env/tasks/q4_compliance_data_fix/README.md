# Task: Q4 Compliance Data Fix

## Overview

**Environment**: AttendHRM (Lenvica HRMS) — Windows 11 desktop HR management system
**Difficulty**: Very Hard
**Domain**: HR Management / Data Quality / Compliance
**Relevant Occupations**: HR Administrators, Payroll Managers, HRIS Specialists

## Real-World Context

HR data quality issues often arise from system migrations and bulk operations. Common failures include employees being assigned to non-existent branches, department assignments getting swapped between employees, and new hire onboarding backlogs. This task simulates a realistic quarterly compliance sweep requiring data fixes and new hire processing.

## Task Description

Three categories of issues must be resolved:

### Issue 1: Invalid Branch Assignments
Four employees have been assigned to branch ID 99 (non-existent) due to a migration error:

| EMP ID | Name | Correct Branch |
|--------|------|---------------|
| 108 | Reid Ryan | London (BRA_ID=101) |
| 120 | Jessica Owens | London (BRA_ID=101) |
| 135 | Daisy Brooks | Norwich (BRA_ID=102) |
| 148 | Jack West | London (BRA_ID=101) |

### Issue 2: Department Swap
Two employees had their departments accidentally swapped:

| EMP ID | Name | Currently In | Should Be In |
|--------|------|-------------|-------------|
| 113 | Miller Russell | Information Technology | Accounts |
| 137 | Ryan Murphy | Accounts | Information Technology |

### Issue 3: Q4 New Hire Import
Five new employees need to be imported from `q4_new_hires.csv` on the Desktop:

| EMP ID | Name | Location | Department |
|--------|------|---------|------------|
| 5001 | Christy Johny | LONDON | Accounts |
| 5002 | Paul Aby | LONDON | Marketing |
| 5003 | Rincy Devassy | NORWICH | Information Technology |
| 5004 | Majeesh Madhavan | NORWICH | Production |
| 5005 | Alex Anto | DUBLIN | Administration |

Names are from AttendHRM's bundled demo dataset.

## Verification Strategy

The export script uses isql.exe to check each employee's current BRA_ID and AFD_ID.

### Scoring (100 points total)

| Criterion | Points | Details |
|-----------|--------|---------|
| 4 branch fixes | 20 pts | 5 pts per employee correctly re-assigned |
| 2 department fixes | 20 pts | 10 pts per employee correctly re-assigned |
| 5 new hires imported | 40 pts | 8 pts per employee (EMP_IDs 5001-5005 in DB) |
| New hires in correct branch | 10 pts | 2 pts each |
| New hires in correct department | 10 pts | 2 pts each |

**Pass threshold**: 70 points
