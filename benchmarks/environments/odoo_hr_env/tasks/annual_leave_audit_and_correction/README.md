# Task: annual_leave_audit_and_correction

## Domain Context

**Environment**: Odoo 17 HR module — Time Off (Leave Management)
**Primary persona**: HR Manager at a professional services firm
**Realistic workflow**: Annual leave entitlement audit. A real HR manager must periodically verify that all employees have been issued the correct leave allocations per company policy and that employee tags are consistent with department assignments. This is a multi-record correction task with heterogeneous starting states (some employees have no PTO, some have insufficient PTO, all are missing the Sales tag).

## Task Overview

Company policy requires all Sales department employees to have: (1) an approved Paid Time Off allocation of at least 20 days, and (2) the 'Sales' employee tag for reporting. The setup seeds 4 Sales employees in deficient states — two with no PTO allocation, two with insufficient allocations (5 and 10 days), and all four missing the Sales tag. The agent must audit and correct all deficiencies.

## Goal (End State)

- All 4 Sales department employees have an approved Paid Time Off allocation of ≥ 20 days
- All 4 Sales department employees have the 'Sales' employee tag

## What the Agent Must Do

The agent must:
1. Navigate to the Sales department employee list (or filter employees by Sales dept)
2. For each Sales employee, check their current PTO allocation status
3. Create/update PTO allocations to reach 20 days and validate/approve them
4. Add the 'Sales' tag to each employee who lacks it

The agent is **not told** which employees are in Sales — it must discover the 4 employees (Keith Byrd, Doris Cole, Tina Williamson, Toni Jimenez) independently.

**Difficulty**: `very_hard` — goal only, no employee names given, heterogeneous states requiring different corrective actions per employee.

## Success Criteria

| Criterion | Points | Partial |
|-----------|--------|---------|
| All 4 employees have approved PTO ≥ 20 days | 60 | 30 (2–3 correct) |
| All 4 employees have 'Sales' tag | 40 | 20 (2–3 with tag) |
| **Total** | **100** | — |
| **Pass threshold** | **60** | — |

**Antipattern 4 check**: max partial = 30+20 = 50 < 60 ✓

## Verification Strategy

`export_result.sh` reads the ground truth from `/tmp/leave_audit_gt.json`, then queries:
1. `hr.leave.allocation` for each target employee — finds max approved days for PTO type
2. `hr.employee.category_ids` for each target employee — checks for Sales tag presence

`verifier.py` reads `/tmp/leave_audit_result.json` via `copy_from_env`.

## Schema / Data Reference

| Odoo model | Field | Description |
|------------|-------|-------------|
| `hr.leave.allocation` | `holiday_status_id` | Leave type (Paid Time Off) |
| `hr.leave.allocation` | `employee_id` | The employee |
| `hr.leave.allocation` | `number_of_days` | Number of days allocated |
| `hr.leave.allocation` | `state` | validate = approved |
| `hr.employee` | `category_ids` | Many2many to hr.employee.category |
| `hr.employee.category` | `name` | Tag name |

## Setup Details

`setup_task.sh` sets 4 specific employees to the Sales department, removes all their Sales tags, and creates deficient/missing PTO allocations:
- **Keith Byrd**: no PTO allocation
- **Doris Cole**: 10-day PTO allocation (insufficient)
- **Tina Williamson**: 5-day PTO allocation (insufficient)
- **Toni Jimenez**: no PTO allocation

All 4 have their Sales tag removed.

## Edge Cases

- Agent may need to reset/refuse an existing allocation before creating a correct 20-day one — this is valid
- The verifier checks for max approved allocation ≥ 20, not exact equality (e.g., agent creating a 25-day allocation is fine)
- Approval workflow: in Odoo, allocations must be validated (not just confirmed) to count as "approved"
