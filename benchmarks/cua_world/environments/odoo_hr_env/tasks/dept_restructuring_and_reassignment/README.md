# Task: dept_restructuring_and_reassignment

## Domain Context

**Environment**: Odoo 17 HR (Human Resources) module
**Primary persona**: General & Operations Manager / HR Manager ($3.29B GDP occupation)
**Realistic workflow**: Organizational restructuring — dissolving a sub-department and consolidating headcount under a parent department. A real HR manager at a technology company would handle this in Odoo by updating each employee's department assignment, their manager relationship, and then archiving the defunct department.

## Task Overview

The company has decided to dissolve the "R&D USA" sub-department. All engineers currently assigned to R&D USA must be migrated to the parent "Research & Development" department. Their manager must be updated to Marc Demo. Once all employees are relocated, R&D USA must be archived.

## Goal (End State)

- All employees previously in R&D USA are now in "Research & Development"
- Each migrated employee has Marc Demo set as their direct manager
- The "R&D USA" department is archived (inactive) in Odoo

## What the Agent Must Do

The agent is **not told** which employees are in R&D USA — it must discover them by browsing the employee list or filtering by department. There are 3 employees to migrate (Walter Horton, Beth Evans, Toni Jimenez), but the agent must find them independently. After migrating all three, the agent must locate the R&D USA department record and archive it.

**Difficulty**: `very_hard` — goal only, no target names given, no UI path given, multiple interdependent subtasks.

## Success Criteria

| Criterion | Points | Partial |
|-----------|--------|---------|
| All 3 employees moved to Research & Development | 35 | 17 (≥2 of 3) |
| All 3 employees have Marc Demo as manager | 35 | 17 (≥2 of 3) |
| R&D USA department is archived | 30 | 0 |
| **Total** | **100** | — |
| **Pass threshold** | **60** | — |

**Antipattern 4 check**: max partial = 17+17+0 = 34 < 60 ✓

## Verification Strategy

`export_result.sh` reads the ground truth from `/tmp/dept_restructuring_gt.json` (written by setup), then queries Odoo via XML-RPC to check:
1. `hr.employee.department_id` for each target employee
2. `hr.employee.parent_id` for each target employee
3. `hr.department.active` for R&D USA

`verifier.py` reads `/tmp/dept_restructuring_result.json` via `copy_from_env` and scores each criterion.

## Schema / Data Reference

| Odoo model | Field | Description |
|------------|-------|-------------|
| `hr.employee` | `department_id` | The employee's current department |
| `hr.employee` | `parent_id` | The employee's direct manager (another hr.employee) |
| `hr.department` | `active` | False = archived |
| `hr.department` | `parent_id` | Parent department |

## Setup Details

`setup_task.sh` places Walter Horton, Beth Evans, and Toni Jimenez in R&D USA with Eli Lambert as their manager (not Marc Demo). Marc Demo is placed in Research & Development. All other employees are moved out of R&D USA so the agent cannot cheat by looking for "all employees" — it must specifically filter by department.

## Edge Cases

- If R&D USA department doesn't exist in demo data, setup creates it as a child of Research & Development
- Partial credit is available (≥2 of 3 employees) to reward agents that make progress but miss one
- Archiving requires navigating to the department's own record (Configuration > Departments), which is a different navigation path than the employee list
