# employee_data_audit

**Difficulty**: very_hard
**Environment**: Sentrifugo v3.2 HRMS (Ubuntu GNOME, Docker MySQL 5.7)
**Domain**: HR compliance / data integrity

## Overview

An HR compliance audit has revealed that four employee records in Sentrifugo contain incorrect department and job title assignments. The agent receives a verified employee roster on the Desktop (`~/Desktop/hr_verified_roster.txt`) listing the ground truth for all 20 employees. The agent must identify the four discrepant records and correct both the department and job title for each affected employee.

The agent is **not told** which employees are wrong — it must compare the roster against the live HRMS data to discover the discrepancies.

## Setup

The setup script injects incorrect department and job title data for four employees (EMP003, EMP007, EMP011, EMP015) by directly updating the database, then drops the verified roster on the Desktop and navigates to the employee list.

## Scoring (100 pts total, pass = 70)

| Criterion | Points |
|-----------|--------|
| EMP003 department correct (Finance & Accounting) | 15 |
| EMP003 job title correct (Finance Manager) | 10 |
| EMP007 department correct (Data Science) | 15 |
| EMP007 job title correct (Senior Data Scientist) | 10 |
| EMP011 department correct (Marketing) | 15 |
| EMP011 job title correct (Marketing Specialist) | 10 |
| EMP015 department correct (DevOps & Infrastructure) | 15 |
| EMP015 job title correct (Systems Engineer) | 10 |

The pass threshold is 70 to prevent passing by fixing only departments without titles (4 × 15 = 60 < 70).

## Verification Strategy

The verifier queries `main_users JOIN main_departments JOIN main_jobtitles` for each of the four employee IDs and compares against the expected values hardcoded in `verifier.py`. Uses `exec_in_env` to run MySQL queries directly against the running `sentrifugo-db` Docker container.

## Anti-Patterns Addressed

- **AP-10**: Setup logs do not reveal which records were injected wrong.
- **AP-13**: Strategy enumeration confirms department-only pass (60 pts) is below the 70-pt threshold.
