# Payroll Wage Audit and Correction

## Overview

A quarterly payroll audit has flagged three employees with incorrect hourly wage rates in TimeTrex. As a Payroll Clerk, you must correct all three wage records before the payroll run is executed. Entering wrong wages causes incorrect paychecks, legal exposure, and manual reversals — this is a high-priority data correction task.

## Goal

Ensure that Victoria Chen (EM-W001), Marcus Williams (EM-W002), and Patricia Nguyen (EM-W003) each have a wage record with the correct hourly rate and an effective date of 2026-01-01 in TimeTrex. The incorrect rates currently in the system are the result of data entry errors at the time of hire.

**Target end state:**
- Victoria Chen: $26.50/hr, effective 2026-01-01
- Marcus Williams: $32.00/hr, effective 2026-01-01
- Patricia Nguyen: $22.75/hr, effective 2026-01-01

## Success Criteria

1. Victoria Chen's wage record reflects $26.50/hr (±$0.01 tolerance)
2. Marcus Williams's wage record reflects $32.00/hr (±$0.01 tolerance)
3. Patricia Nguyen's wage record reflects $22.75/hr (±$0.01 tolerance)

Each employee is worth ~33 points. All three correct = 100 points. Partial credit is awarded per employee corrected.

## Verification Strategy

`export_result.sh` queries `user_wage JOIN users` by employee number (EM-W001/002/003), fetching the most recent `effective_date DESC` wage row. The verifier compares the numeric wage values within a tolerance of ±$0.005.

## Schema Reference

```sql
-- Employees
SELECT id FROM users WHERE employee_number = 'EM-W001' AND deleted = 0;

-- Wage records
SELECT wage, effective_date
FROM user_wage
WHERE user_id = <id> AND deleted = 0
ORDER BY effective_date DESC LIMIT 1;

-- type_id = 10 (Hourly)
```

## Edge Cases

- The agent may add a new wage row rather than editing the existing one; the verifier accepts either approach (it takes the most recent `effective_date DESC` row).
- If the agent accidentally deletes the employee or sets deleted=1 on the wage record, the verifier reports no wage found (0 pts for that employee).
- Effective date is noted in feedback but not scored separately; the primary check is the wage amount.

## Starting State (seeded by setup_task.sh)

| Employee | Emp # | Injected (wrong) wage | Correct wage |
|----------|-------|----------------------|-------------|
| Victoria Chen | EM-W001 | $18.00/hr | $26.50/hr |
| Marcus Williams | EM-W002 | $24.00/hr | $32.00/hr |
| Patricia Nguyen | EM-W003 | $15.00/hr | $22.75/hr |

All three employees are active (status_id=10). Company ID is inherited from existing demo data.
