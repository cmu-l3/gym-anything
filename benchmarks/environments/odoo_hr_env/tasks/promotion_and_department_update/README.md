# Task: promotion_and_department_update

## Domain Context

**Environment**: Odoo 17 HR module — Employees, Departments, Job Positions, Tags
**Primary persona**: General & Operations Manager ($3.29B GDP occupation)
**Realistic workflow**: Annual performance review outcomes require batch HR changes: promotions (job position + department changes), role reclassifications, bulk tag assignments, and department management updates. A real Ops Manager must implement these decisions in the HR system without delay after the review cycle closes.

## Task Overview

The annual personnel review has concluded with four decisions that must be implemented in Odoo:
1. Ronnie Hart is promoted to CTO and transferred to Management (under Marc Demo)
2. Jennie Fletcher's role is reclassified to HR Manager
3. All Long Term Projects employees must be tagged as Consultants
4. Randall Lewis is formally designated as Long Term Projects department manager

## Goal (End State)

- **Ronnie Hart**: Job Position = CTO, Department = Management, Manager = Marc Demo
- **Jennie Fletcher**: Job Position = HR Manager
- **All Long Term Projects employees**: have 'Consultant' tag
- **Long Term Projects department**: `manager_id` = Randall Lewis

**Difficulty**: `very_hard` — 4 independent personnel changes, each requiring navigation to different records; step 3 requires discovering which employees are in Long Term Projects (the agent is not told).

## Success Criteria

| Criterion | Points | Partial |
|-----------|--------|---------|
| Ronnie Hart: CTO + Management dept | 30 | 15 (only one of the two correct) |
| Jennie Fletcher: HR Manager position | 20 | 0 |
| All LTP employees have Consultant tag | 30 | 15 (≥1 but not all have tag) |
| LTP dept manager = Randall Lewis | 20 | 0 |
| **Total** | **100** | — |
| **Pass threshold** | **60** | — |

**Antipattern 4 check**: max partial = 15+0+15+0 = 30 < 60 ✓

## Verification Strategy

`export_result.sh` queries:
1. Ronnie Hart's `job_id` and `department_id` fields
2. Jennie Fletcher's `job_id` field
3. Each LTP employee's `category_ids` for Consultant tag presence
4. Long Term Projects department's `manager_id` field

`verifier.py` reads `/tmp/promotion_result.json` via `copy_from_env`.

## Schema / Data Reference

| Odoo model | Field | Description |
|------------|-------|-------------|
| `hr.employee` | `job_id` | Many2one to hr.job (Job Position) |
| `hr.employee` | `department_id` | Many2one to hr.department |
| `hr.employee` | `parent_id` | Many2one to hr.employee (direct manager) |
| `hr.employee` | `category_ids` | Many2many to hr.employee.category (Tags) |
| `hr.department` | `manager_id` | Many2one to hr.employee (department manager) |

**Important distinction**: `hr.department.manager_id` is the **department manager** field set on the department record itself (Configuration > Departments). This is different from `hr.employee.parent_id`, which is the employee's personal direct manager. Both may exist simultaneously and both may need to be set.

## Setup Details

`setup_task.sh`:
- Ronnie Hart: placed in R&D dept with Experienced Developer job (NOT CTO, NOT Management)
- Jennie Fletcher: job set to Consultant (NOT HR Manager)
- Randall Lewis, Ernest Reed, Paul Williams: placed in Long Term Projects; Consultant tag removed
- Long Term Projects dept: manager cleared (NOT Randall Lewis)
- Marc Demo: confirmed in Management department
- HR Manager job position created if it doesn't exist

## Edge Cases

- "Long Term Projects department manager" must be set on the **department record** (Configuration > Departments > Long Term Projects), not just on an employee's personal manager field
- Ronnie Hart's Marc Demo manager requirement is assessed separately from the job/dept criterion; even partial credit (just CTO or just Management) is rewarded
- Consultant tag must be present on each LTP employee's profile, not just the department record
