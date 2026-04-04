# Task: Employee Expense Approval

## Difficulty: Hard

## Occupation Context
**Primary occupations**: General & Operations Managers ($3.29B GDP), Human Resource Managers ($415M GDP)
**Why realistic**: Approving and reimbursing employee expenses is a routine HR/finance workflow. The three-step Odoo process — manager approval → accounting journal posting → payment registration — mirrors real accounts-payable procedures for employee reimbursements.

## Scenario
Sarah Mitchell submitted an expense report for her Q1 client visit to Chicago. The report ("Q1 Client Visit - Chicago") covers hotel accommodation, business meals, and airfare totaling $1,117.50. It has been submitted and is awaiting manager action. The agent must:

1. **Find** Sarah Mitchell's submitted expense report in Odoo
2. **Approve** the expense report (manager approval step)
3. **Post** the accounting journal entries ("Post Journal Entries" button)
4. **Register** the reimbursement payment to the employee

## Why This Is Hard
- Multi-step sequential workflow: each step unlocks the next
- The agent must recognise that "approve" alone is insufficient — posting and payment are separate actions
- Finding the right module (Expenses) and navigating the approval workflow requires familiarity with Odoo HR

## Setup Details
`setup_task.sh` performs:
1. Verifies `hr_expense` module is installed (attempts install if missing)
2. Creates employee **Sarah Mitchell** with a home address
3. Finds expensable products (or creates "Hotel & Accommodation" as fallback)
4. Creates three expense line items:
   - Hotel & Accommodation: $285 × 2 nights = $570.00
   - Business Meals: $127.50 × 1 = $127.50
   - Travel / Airfare: $420.00 × 1 = $420.00
5. Creates expense sheet **"Q1 Client Visit - Chicago"** and submits it (state: `submit`)

| Expense | Unit Price | Qty | Amount |
|---------|-----------|-----|--------|
| Hotel & Accommodation | $285.00 | 2 | $570.00 |
| Business Meals | $127.50 | 1 | $127.50 |
| Travel / Airfare | $420.00 | 1 | $420.00 |
| **Total** | | | **$1,117.50** |

## Verification Criteria (100 points)
| Criterion | Points | Check |
|-----------|--------|-------|
| Expense report approved | 30 | `sheet_state in ['approve', 'post', 'done']` |
| Journal entries posted | 30 | `is_posted == True` (state in ['post', 'done'] or linked journal move posted) |
| Payment registered to employee | 40 | `is_paid == True` (state='done' or payment_state in ['paid', 'in_payment']) |
| **Pass threshold** | **70** | **Must score ≥70 AND payment registered** |

**Score gate**: If payment is not registered, score is capped at 69 (cannot pass without completing the full reimbursement cycle).

## Workflow Steps in Odoo
```
Expenses → My Team's Expenses (or All Expenses)
→ Find "Q1 Client Visit - Chicago" (Sarah Mitchell)
→ Approve [button] → sheet state: approve
→ Post Journal Entries [button] → state: post
→ Register Payment [button] → state: done
```

## Key Odoo Tables
- `hr.expense.sheet` — expense reports (state: draft → submit → approve → post → done)
- `hr.expense` — individual expense line items (sheet_id → expense sheet)
- `account.move` — linked journal entries (state: draft → posted)
- `hr.employee` — employee records (address_home_id for payment)

## Features Exercised
- HR Expenses module: submit → approve → post → pay workflow
- Accounting integration: journal entry creation on posting
- Payment registration: employee reimbursement via bank journal
