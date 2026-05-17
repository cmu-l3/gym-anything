# leave_audit_q3_corrections

**Difficulty:** very_hard  
**Timeout:** 720 s / 90 steps  
**Reward type:** sparse

## Domain context

Leave administrators and HR Compliance Officers conduct periodic audits of time-off policies and employee allocations to catch configuration drift, policy violations, and missing entitlements before payroll cut-off. This task mirrors a realistic Q3 audit cycle where four distinct compliance issues have accumulated and must be resolved in a single session.

## Goal (end state)

After resolving the four issues discovered during the Q3 audit:

1. The "Paid Time Off" leave type's approval workflow must be set to require manager sign-off (currently bypassed).
2. Two confirmed leave requests that were submitted without obtaining the now-required manager approval must be refused.
3. An employee in the Research & Development department who has no Paid Time Off allocation must receive a correctly-sized validated allocation.
4. Another employee's Paid Time Off allocation exceeds the company's 15-day annual cap and must be corrected.

## Success criteria

| Criterion | Points |
|-----------|--------|
| C1: Paid Time Off `leave_validation_type` = `'manager'` | 25 |
| C2: Ernest Reed's leave request refused | 15 |
| C3: Ronnie Hart's leave request refused | 15 |
| C4: Eli Lambert has a validated 15-day PTO allocation | 25 |
| C4 partial: allocation exists but not validated / wrong days | 10 |
| C5: Walter Horton's allocation reduced to ≤ 15 days | 20 |
| **Pass threshold** | **≥ 65** |

Maximum partial score without crossing the threshold: 10 pts (C4 partial only).

## Verification strategy

`export_result.sh` reads via XML-RPC:
- `hr.leave.type` — checks `leave_validation_type` for Paid Time Off
- `hr.leave` — checks `state` for Ernest Reed's and Ronnie Hart's seeded leave requests
- `hr.leave.allocation` — lists all Eli Lambert PTO allocations (checks state + days) and reads Walter Horton's specific allocation days

Ground truth IDs written to `/tmp/leave_audit_gt.json` by setup.

## Data notes

Uses Odoo demo employees (Ernest Reed, Ronnie Hart, Eli Lambert, Walter Horton) and the built-in "Paid Time Off" leave type. Leave requests and allocations are seeded in setup_task.sh. The 15-day cap reflects SHRM survey data for median US PTO caps at mid-size companies.

## Edge cases

- Setup removes all existing Eli Lambert PTO allocations so the agent starts from zero.
- Walter Horton's allocation is seeded as validated (20 days) — the agent must reduce it, not simply create a new one.
- `leave_validation_type` values in Odoo 17: `'no_validation'`, `'manager'`, `'hr'`, `'both'`.
