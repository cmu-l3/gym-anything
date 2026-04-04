# Task: new_hire_complete_onboarding

## Domain Context

**Environment**: Odoo 17 HR module — Employee Records, Leave Allocations
**Primary persona**: HR Manager / HR Specialist
**Realistic workflow**: New hire onboarding requires filling in an employee's complete HR profile across multiple tabs (Work Information, Private Information, HR Settings), assigning them to the correct team, and provisioning their initial leave entitlements. This is a breadth task — many distinct fields across multiple module areas.

## Task Overview

Jordan Kim has been added as a placeholder employee with only their name filled in. The HR Manager must complete the full onboarding profile: work information (job, department, manager, coach, contact), employee tags, and leave allocations (both PTO and Compensatory Days).

## Goal (End State)

Jordan Kim's employee record must have:
- Job Position: Experienced Developer
- Department: Research & Development
- Manager: Marc Demo
- Coach: Eli Lambert
- Work Phone: +1 555 234 5678
- Work Email: jordan.kim@company.com
- Tags: Employee, Trainer
- Approved Paid Time Off allocation: 20 days
- Approved Compensatory Days allocation: 5 days

**Difficulty**: `very_hard` — many fields spread across multiple tabs and a separate Time Off module, requiring navigation across multiple application areas.

## Success Criteria

| Criterion | Points | Partial |
|-----------|--------|---------|
| Job Position = Experienced Developer AND Dept = R&D | 20 | 10 (one of two) |
| Manager = Marc Demo AND Coach = Eli Lambert | 20 | 10 (one of two) |
| Work phone AND work email correct | 15 | 0 |
| Both 'Employee' and 'Trainer' tags assigned | 15 | 7 (one of two tags) |
| PTO ≥ 20 days AND Comp Days ≥ 5 days (approved) | 30 | 15 (one of two allocs) |
| **Total** | **100** | — |
| **Pass threshold** | **60** | — |

**Antipattern 4 check**: max partial = 10+10+0+7+15 = 42 < 60 ✓

## Verification Strategy

`export_result.sh` reads Jordan Kim's employee record fields, checks tag assignments, and queries `hr.leave.allocation` for both PTO and Compensatory Days leave types.

`verifier.py` reads `/tmp/onboarding_result.json` via `copy_from_env`. Phone comparison is flexible (strips non-digit characters for matching). Ground truth IDs for job, dept, manager, coach, tags are passed through from the export result.

## Schema / Data Reference

| Odoo model | Field | Description |
|------------|-------|-------------|
| `hr.employee` | `job_id` | Many2one to hr.job (Job Position) |
| `hr.employee` | `department_id` | Many2one to hr.department |
| `hr.employee` | `parent_id` | Many2one to hr.employee (Manager) |
| `hr.employee` | `coach_id` | Many2one to hr.employee (Coach) |
| `hr.employee` | `work_phone` | Work phone number |
| `hr.employee` | `work_email` | Work email address |
| `hr.employee` | `category_ids` | Many2many to hr.employee.category (Tags) |
| `hr.leave.allocation` | `holiday_status_id` | Leave type (PTO / Compensatory Days) |
| `hr.leave.allocation` | `state` | validate = approved |
| `hr.leave.allocation` | `number_of_days` | Days allocated |

## Setup Details

`setup_task.sh`:
1. Removes any existing Jordan Kim employee records (clean slate)
2. Creates a new employee with ONLY `name = 'Jordan Kim'` — all other fields are blank
3. Verifies Marc Demo, Eli Lambert, Experienced Developer job position exist
4. Ensures 'Employee' and 'Trainer' tags exist

## Edge Cases

- Job Position field in Odoo is `hr.job` (many2one), distinct from the free-text `job_title` field
- Coach is a separate field from Manager — agent must set both
- Leave allocations must be approved (validated), not just created/confirmed
- Two separate allocations required: one for Paid Time Off, one for Compensatory Days
- Phone number matching is flexible (strips non-digit chars) to allow different formatting
