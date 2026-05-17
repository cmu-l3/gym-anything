# expense_monthly_audit_june

**Difficulty:** very_hard  
**Timeout:** 720 s / 90 steps  
**Reward type:** sparse

## Domain context

Accounts Payable and HR Finance teams run monthly expense audits before payroll close to catch policy violations, duplicate claims, and misconfigured expense categories. A typical session involves reviewing submitted reports for over-limit line items, checking claim history against paid reports, correcting product configuration, and processing legitimate draft reports that employees have not yet submitted. This task reflects a realistic June audit with all four issues present simultaneously.

## Goal (end state)

After completing the June expense audit:

1. The "Conference Registration" expense category must be configured as reimbursable so employees can include it in future reports.
2. A submitted expense report from an R&D employee that contains a single airfare line item exceeding the $500 per-item reimbursement cap must be refused.
3. A separate submitted expense report that contains a line item with a description identical to a claim already reimbursed last month by the same employee must be refused as a duplicate.
4. A draft expense report from another R&D employee that has been sitting unsubmitted must be submitted and approved.

## Success criteria

| Criterion | Points |
|-----------|--------|
| C1: "Conference Registration" product `can_be_expensed = True` | 20 |
| C2: Eli Lambert's draft report approved (state `approve`/`post`/`done`) | 20 |
| C2 partial: report submitted but not approved | 10 |
| C3: Rachel Perry's over-cap report refused (state `cancel`) | 30 |
| C4: Marc Demo's duplicate-claim report refused (state `cancel`) | 30 |
| **Pass threshold** | **≥ 65** |

Maximum partial score without crossing the threshold: 10 pts (C2 submitted partial only).

## Verification strategy

`export_result.sh` reads via XML-RPC:
- `product.product` — checks `can_be_expensed` for the seeded Conference Registration product
- `hr.expense.sheet` — checks `state` for Eli Lambert's, Rachel Perry's, and Marc Demo's sheets

Ground truth written to `/tmp/expense_audit_gt.json` by setup.

## Data notes

Setup creates: a "Conference Registration" product with `can_be_expensed=False`; a prior "done" Marc Demo expense sheet from May with a specific description; Eli Lambert's draft sheet; Rachel Perry's submitted sheet (single $650 item, over the $500 cap); Marc Demo's June submitted sheet (verbatim duplicate description of the May item). Expense amounts are grounded in typical US corporate travel costs for 2025 (domestic airfare $550–700, team dinners $150–200).

## Edge cases

- `hr.expense.sheet` "refused" state is represented as `'cancel'` in Odoo 17.
- The duplicate check relies on identical expense line-item descriptions between May and June sheets — the agent must inspect the previous month's history.
- Advancing Marc Demo's prior sheet to "done" state requires submit → approve → post (accounting move); partial advances are acceptable for setup purposes.
