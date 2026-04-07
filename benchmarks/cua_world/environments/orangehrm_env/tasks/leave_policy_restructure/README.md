# Task: leave_policy_restructure

## Domain Context

**Occupation**: HR Managers, HR Assistants, First-Line Supervisors of Office and Admin Support
**Industry**: Human Resources Management (OrangeHRM 5.8, MariaDB 10.11)
**Realistic scenario**: A payroll audit reveals that Finance department employees received erroneous 30-day Annual Leave entitlements (policy is 12 days), and Sick Leave was never allocated for the current year. Additionally, the board approved a new "Compensatory Time Off" leave type that must be added to the system.

This mirrors real HR leave administration work that HR Assistants (importance=91) perform during quarterly audits.

---

## Goal

The agent must:
1. Create the "Compensatory Time Off" leave type (it is missing from the system)
2. Correct the Annual Leave entitlement for each Finance department employee from 30 days → 12 days
3. Add a 10-day Sick Leave entitlement for the current year to each Finance department employee

Finance department employees: David Nguyen (EMP003), Amanda Davis (EMP010), Brian Taylor (EMP017)

---

## Starting State (Injected by setup_task.sh)

- Finance employees (EMP003, EMP010, EMP017) have Annual Leave set to **30 days** (wrong; policy = 12)
- Finance employees have **no Sick Leave** entitlement for the current year
- "Compensatory Time Off" leave type **does not exist** in the system

---

## Success Criteria

| Criterion | Points |
|-----------|--------|
| "Compensatory Time Off" leave type created and active | 20 |
| EMP003 Annual Leave == 12 days for current year | 12 |
| EMP010 Annual Leave == 12 days for current year | 12 |
| EMP017 Annual Leave == 12 days for current year | 12 |
| Bonus: all 3 AL corrections perfect | 11 |
| EMP003 Sick Leave >= 10 days for current year | 11 |
| EMP010 Sick Leave >= 10 days for current year | 11 |
| EMP017 Sick Leave >= 10 days for current year | 11 |
| **Pass threshold** | **60** |

Partial credit: Annual Leave partially reduced (but not to 12) = 5 pts each. Sick Leave > 0 but < 10 = 5 pts each.

---

## Verification Strategy

**Export** (`export_result.sh`): Checks `ohrm_leave_type` for Compensatory Time Off. Sums `ohrm_leave_entitlement.no_of_days` grouped by emp_number and leave_type_id for the current calendar year.

**Verifier** (`verifier.py`): Reads `/tmp/leave_policy_restructure_result.json`. Scores each criterion independently. Tolerance: AL days within 0.5 of 12.0 count as correct.

---

## Key DB Schema

```sql
-- Leave types
SELECT id, name FROM ohrm_leave_type WHERE deleted=0;

-- Leave entitlements
SELECT emp_number, no_of_days, leave_type_id
FROM ohrm_leave_entitlement
WHERE emp_number IN (E3, E10, E17) AND deleted=0
  AND to_date >= '2026-01-01' AND from_date <= '2026-12-31';

-- Finance employees
SELECT emp_number FROM hs_hr_employee
WHERE employee_id IN ('EMP003', 'EMP010', 'EMP017') AND purged_at IS NULL;
```

---

## Edge Cases

- OrangeHRM only allows editing leave entitlements that were created as "Added" type (entitlement_type=1); the UI may show the allocation on the Leave > Entitlements page
- If the agent creates a NEW entitlement at 12 days instead of editing the existing 30-day one, the total may become 42; the verifier sums all active entitlements — the agent must ensure the total is 12, not just add 12
- "Sick Leave" already exists as a leave type in the system (seeded); the agent does not need to create it, only allocate entitlements
