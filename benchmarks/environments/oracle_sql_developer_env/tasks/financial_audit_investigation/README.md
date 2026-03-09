# Financial Compliance Audit Investigation

## Domain Context

Compliance officers at corporations regularly audit HR and finance systems for policy violations. A critical audit function is verifying that employee compensation falls within approved job-grade ranges, detecting duplicate or fraudulent expense submissions, and ensuring that an automated audit trail captures all future salary changes. This task reflects a real-world compliance workflow that professionals in roles such as Compliance Officer, Internal Auditor, or HR Data Analyst perform against enterprise Oracle databases.

## Task Overview

The compliance department has detected anomalies in the HR system. You must conduct a full database audit using Oracle SQL Developer:

1. **Salary Policy Violations**: Query the EMPLOYEES table and JOBS table to identify all employees whose current salary falls outside the MIN_SALARY or MAX_SALARY for their job title. The job salary ranges are in the JOBS table.
2. **Duplicate Expense Submissions**: Inspect the EXPENSE_REPORTS table for duplicate submissions — same employee, same date, same amount, and same expense type submitted more than once.
3. **Salary Change Audit Trigger**: Create a PL/SQL trigger named `SALARY_AUDIT_TRG` on the EMPLOYEES table that fires on AFTER UPDATE OF SALARY, logging the employee_id, old salary, new salary, changed_by user, and change timestamp to the SALARY_CHANGE_LOG table (already created for you).
4. **Findings Report**: Export your compliance findings to `/home/ga/Documents/exports/audit_findings.csv`.

## Credentials

- HR schema: `hr` / `hr123`
- System: `system` / `OraclePassword123`

## Success Criteria

- The `SALARY_AUDIT_TRG` trigger exists on HR.EMPLOYEES, is ENABLED, and fires on salary UPDATE
- The `SALARY_CHANGE_LOG` table exists and has appropriate columns for tracking changes
- The audit findings CSV file exists at `/home/ga/Documents/exports/audit_findings.csv` with content
- SQL Developer GUI was used to perform the analysis

## Verification Strategy

- **Trigger existence**: `ALL_TRIGGERS` view checked for `SALARY_AUDIT_TRG` on `EMPLOYEES` table with status ENABLED
- **Log table**: `ALL_TAB_COLUMNS` checked for `SALARY_CHANGE_LOG` with salary-tracking columns
- **CSV file**: File existence and size checked; content verified for violation data
- **GUI usage**: SQL history, MRU cache, active sessions checked

## Schema Reference

```sql
-- Key tables
HR.EMPLOYEES  (employee_id, first_name, last_name, salary, job_id, department_id, ...)
HR.JOBS       (job_id, job_title, min_salary, max_salary)
HR.EXPENSE_REPORTS (report_id, employee_id, submission_date, expense_type, amount, description, status)
HR.SALARY_CHANGE_LOG (pre-created: log_id, employee_id, old_salary, new_salary, changed_by, change_date)
```

## Difficulty: very_hard

The agent must independently:
- Discover which employees are in violation (not told which ones)
- Identify the duplicate submission pattern (not told which records)
- Write PL/SQL trigger code from scratch
- Export formatted findings to CSV
