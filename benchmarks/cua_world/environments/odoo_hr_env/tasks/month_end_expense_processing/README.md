# Task: month_end_expense_processing

## Domain Context

**Environment**: Odoo 17 HR module — Expenses
**Primary persona**: Finance Manager / Treasurer & Controller ($1.61B GDP occupation)
**Realistic workflow**: Month-end expense processing is a standard finance workflow. Individual employees submit draft expense records; the Finance Manager must convert them to expense reports, submit them for approval, and selectively approve pre-authorized expenses. This tests multi-entity workflow chaining and selective approval (a judgment call).

## Task Overview

Three employees (Anita Oliver, Sharlene Rhodes, Paul Williams) have draft individual expenses in the system that need to be converted into expense reports and submitted. Paul Williams's expenses have been pre-authorized and must also be approved. The others should remain in submitted state awaiting normal approval.

## Goal (End State)

- Anita Oliver: expense report exists with state = submitted (or beyond)
- Sharlene Rhodes: expense report exists with state = submitted (or beyond)
- Paul Williams: expense report exists with state = **approved** (not just submitted)

## What the Agent Must Do

1. Navigate to Expenses module → find draft expenses for Anita Oliver
2. Create an expense report from her draft expense and submit it
3. Navigate to find draft expenses for Sharlene Rhodes
4. Create an expense report and submit it
5. Navigate to find draft expenses for Paul Williams
6. Create an expense report and submit it
7. **Go back** to Paul Williams's submitted expense report and approve it (validate)

The agent must distinguish Paul's report from the others — only his gets approved.

**Difficulty**: `very_hard` — multi-employee workflow chaining, selective approval requiring judgment (which report gets approved), different final states required per employee.

## Success Criteria

| Criterion | Points | Partial |
|-----------|--------|---------|
| Anita Oliver: expense report submitted+ | 25 | 0 |
| Sharlene Rhodes: expense report submitted+ | 25 | 0 |
| Paul Williams: expense report approved+ | 50 | 20 (submitted only) |
| **Total** | **100** | — |
| **Pass threshold** | **60** | — |

**Antipattern 4 check**: max partial = 0+0+20 = 20 < 60 ✓
**Note**: Agent cannot pass with only C1+C2 (25+25=50 < 60); must also at least submit Paul's.

## Verification Strategy

`export_result.sh` queries `hr.expense.sheet` for each of the 3 employees, finding the sheet with the most advanced state. It checks against Odoo's expense sheet states: draft → submit → approve → post → done.

`verifier.py` reads `/tmp/expense_processing_result.json` via `copy_from_env`.

## Schema / Data Reference

| Odoo model | Field | Description |
|------------|-------|-------------|
| `hr.expense` | `employee_id` | The employee who incurred the expense |
| `hr.expense` | `sheet_id` | The expense report this expense belongs to (False = draft) |
| `hr.expense` | `name` | Expense description |
| `hr.expense` | `total_amount` | Total expense amount |
| `hr.expense.sheet` | `employee_id` | The employee |
| `hr.expense.sheet` | `state` | draft/submit/approve/post/done |

### Expense Sheet States
- `draft`: Created but not submitted
- `submit`: Submitted for approval
- `approve`: Approved by manager
- `post`: Posted to accounting
- `done`: Expense paid

## Setup Details

`setup_task.sh` creates one draft expense for each of the 3 target employees:
- **Anita Oliver**: "Client Entertainment - Q4", $120.00
- **Sharlene Rhodes**: "Travel - Client Site Visit", $340.00
- **Paul Williams**: "Training Materials and Certification", $85.00

All existing expenses and expense reports for these employees are cleared first.

## Edge Cases

- The agent must know that "approve" in Odoo requires using the "Approve" button, not just a status change
- Expense reports can only be approved from the "submitted" state (not from draft)
- If agent creates expense report without the draft expense attached, the expense report may be empty
