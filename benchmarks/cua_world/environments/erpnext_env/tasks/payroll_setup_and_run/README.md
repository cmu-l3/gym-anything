# Task: payroll_setup_and_run

**Difficulty**: very_hard
**Environment**: erpnext_env
**Occupation alignment**: Accountants and Auditors (importance=86, GDP=$228M)

## Overview

Wind Power LLC's Engineering department (Michał Sobczak, Vakhita Ryzaev) has no payroll configuration. The agent must build the complete payroll pipeline from scratch and run it for the current month.

## Setup State

- Engineering department exists
- Michał Sobczak and Vakhita Ryzaev are employees in Engineering department
- A Payroll Period for the current month is created
- **No Salary Structure or Payroll Entry exists for these employees**
- Browser is open to the Salary Structure list

## Required Agent Actions (in order)

1. Create **Salary Components** (at least one Earning, e.g., Basic Pay; one Deduction, e.g., Tax)
2. Create a **Salary Structure** using those components (submit it)
3. Create **Salary Structure Assignments** for both Engineering employees
4. Create a **Payroll Entry** for Engineering department for the current month (submit it)
5. Generate and submit **Salary Slips** for both employees

## Scoring (100 pts, pass >= 70)

| Criterion | Points | Check |
|-----------|--------|-------|
| C1: New Salary Structure submitted with >= 2 components | 25 | Export queries SS |
| C2: Salary Structure assigned to both Engineering employees | 25 | Export queries SSA |
| C3: Payroll Entry submitted for Engineering | 25 | Export queries PE |
| C4: Salary Slips submitted for both employees, net_pay > 0 | 25 | Export queries Salary Slip |

## Key ERPNext Workflow Notes

- Navigate: Payroll > Salary Component → create Basic Pay (Earning) and Income Tax (Deduction)
- Navigate: Payroll > Salary Structure → create structure with components
- Navigate: Payroll > Salary Structure Assignment → assign to each employee with a base salary
- Navigate: Payroll > Payroll Entry → select department=Engineering, date range, get employees, submit
- From Payroll Entry, click "Create Salary Slips" then submit each one

## Files

- `task.json` — task metadata and init config
- `setup_task.sh` — creates department, employees, payroll period
- `export_result.sh` — queries ERPNext for SS/SSA/PE/Slips, writes result JSON
- `verifier.py` — scores based on exported result JSON
