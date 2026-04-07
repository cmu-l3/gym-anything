# org_structure_setup

**Difficulty**: very_hard
**Environment**: Sentrifugo v3.2 HRMS (Ubuntu GNOME, Docker MySQL 5.7)
**Domain**: HR organizational design / new department launch

## Overview

The CEO has approved a new Product Management department as part of the company's strategic expansion. The agent receives a department charter document on the Desktop (`~/Desktop/department_charter.txt`) that specifies the new department details, three job titles to create, and three employees to onboard — all from scratch. Nothing exists in the HRMS at task start.

The agent must navigate through multiple UI areas: create the department, create each job title, then add each employee with the correct department and job title assignment.

## Setup

The setup script removes any prior-run artifacts (EMP021/EMP022/EMP023 employees, PM department, VP-PROD/SR-PM/PM-JR titles), then drops the charter document on the Desktop and navigates to the Departments page.

## Scoring (100 pts total, pass = 60)

| Criterion | Points |
|-----------|--------|
| Department "Product Management" active | 15 |
| Job title "VP of Product" active | 10 |
| Job title "Senior Product Manager" active | 10 |
| Job title "Product Manager" active | 10 |
| EMP021 Marcus Webb exists, active, in Product Management | 18 |
| EMP022 Priya Sharma exists, active, in Product Management | 18 |
| EMP023 Lucas Fernandez exists, active, in Product Management | 19 |

Employee scoring is binary — employees in the wrong department receive 0 pts (not partial).

## Verification Strategy

The verifier queries `main_departments`, `main_jobtitles`, and `main_users JOIN main_departments` to check each criterion. Uses `exec_in_env` for live MySQL queries. Employee lookup falls back to first+last name if employeeId lookup fails.

## Anti-Patterns Addressed

- **AP-8**: Employee scoring is binary to prevent "create dept + all titles + all wrong-dept employees" (72 pts) from passing with 0 employees in the correct department.
