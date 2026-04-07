# Task: complete_employee_onboarding

## Domain Context

**Occupation**: HR Managers, HR Assistants, Administrative Services Managers
**Industry**: Human Resources Management (OrangeHRM 5.8, MariaDB 10.11)
**Realistic scenario**: An HR Manager receives a memo with two new hire details and must onboard them fully into the HRMS: create their employee records, assign departments and job titles, add emergency contacts (compliance requirement), and allocate annual leave. The spec file on the Desktop represents the paper memo or email the HR person received.

This is a Specification-Driven Discovery task — the agent must find and read the spec file before acting.

---

## Goal

The agent must find `/home/ga/Desktop/new_hire_spec.txt`, read it, and for each of the two new hires:
1. Create the employee record (first name, last name, employee ID, work email, work phone)
2. Assign the correct job title and department
3. Add at least one emergency contact (name, relationship, phone)
4. Add an Annual Leave entitlement of 15 days for the current calendar year

**New hires specified in the file:**
- Alex Chen — EMP021, Marketing Specialist, Marketing department
- Maria Santos — EMP022, Financial Analyst, Finance department

---

## Starting State (Injected by setup_task.sh)

- Any prior records for EMP021 / Alex Chen and EMP022 / Maria Santos are **purged**
- The spec file `/home/ga/Desktop/new_hire_spec.txt` is **created** with all new hire details

---

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Alex Chen employee record created | 20 |
| Alex Chen assigned to Marketing department | 10 |
| Alex Chen has >= 1 emergency contact | 10 |
| Alex Chen Annual Leave >= 15 days | 10 |
| Maria Santos employee record created | 20 |
| Maria Santos assigned to Finance department | 10 |
| Maria Santos has >= 1 emergency contact | 10 |
| Maria Santos Annual Leave >= 15 days | 10 |
| **Pass threshold** | **60** |

Partial credit: Annual Leave > 0 but < 15 = 5 pts.

---

## Verification Strategy

**Export** (`export_result.sh`): Looks up employees by employee_id (EMP021/EMP022) or by name. Queries `ohrm_subunit` via `hs_hr_employee.work_unit` for department. Counts `hs_hr_emp_emergency_contacts`. Sums `ohrm_leave_entitlement.no_of_days` for Annual Leave.

**Verifier** (`verifier.py`): Reads `/tmp/complete_employee_onboarding_result.json`. Department check is case-insensitive substring match ("marketing", "finance").

---

## Key DB Schema

```sql
-- Find new employees
SELECT emp_number, employee_id, emp_firstname, emp_lastname, work_unit
FROM hs_hr_employee
WHERE employee_id IN ('EMP021', 'EMP022') AND purged_at IS NULL;

-- Department via work_unit
SELECT s.name FROM hs_hr_employee e
JOIN ohrm_subunit s ON e.work_unit = s.id
WHERE e.employee_id = 'EMP021' AND e.purged_at IS NULL;

-- Emergency contacts
SELECT COUNT(*) FROM hs_hr_emp_emergency_contacts WHERE emp_number = ?;

-- Annual Leave entitlement (summed for current year)
SELECT SUM(no_of_days) FROM ohrm_leave_entitlement
WHERE emp_number = ? AND leave_type_id = (SELECT id FROM ohrm_leave_type WHERE name='Annual Leave' AND deleted=0)
  AND deleted = 0 AND to_date >= '2026-01-01';
```

---

## Edge Cases

- The spec file is plain text at `/home/ga/Desktop/new_hire_spec.txt`; the agent can open it with any text viewer or read it via the terminal
- The agent must discover the file on its own — the task description mentions the Desktop but not the exact filename
- If the agent creates the employee with a slightly different employee_id, the verifier falls back to name matching (first+last name)
- Job title must be set on the employee profile's "Job" tab; department is also on the "Job" tab
- Leave entitlements are added via Leave > Entitlements > Add Entitlements (not directly on the employee profile)
