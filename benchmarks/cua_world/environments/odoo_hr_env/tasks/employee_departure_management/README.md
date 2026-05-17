# employee_departure_management

**Difficulty:** very_hard  
**Timeout:** 720 s / 90 steps  
**Reward type:** sparse

## Domain context

HR Business Partners handle employee offboarding according to a defined checklist that spans multiple Odoo modules: reassigning direct reports, blocking open expense claims, triggering the departure workflow, and logging confirmation notes for compliance. This task models the immediate-departure scenario where all closure steps must be completed in a single session before the employee's system access expires.

## Goal (end state)

A department manager in the Management division has resigned effective today. Before her record is closed:

1. Her two direct reports must be reassigned to a different active manager (their `parent_id` must no longer point to her).
2. Her submitted expense report must be refused — it cannot be processed after departure.
3. Her employee record must be archived using the departure workflow, with a departure reason and effective date recorded.
4. A note must be posted in her employee chatter confirming that her remaining paid-time-off balance has been reviewed.

## Success criteria

| Criterion | Points |
|-----------|--------|
| C1a: Rachel Perry reassigned to a different manager | 15 |
| C1b: Doris Cole reassigned to a different manager | 10 |
| C2: Departing manager's expense sheet refused (state `cancel`) | 20 |
| C3: Employee archived (`active = False`) | 30 |
| C4: `departure_reason_id` set (not null) | 15 |
| C5: Chatter note referencing leave/PTO/balance posted | 10 |
| **Pass threshold** | **≥ 65** |

Maximum partial score without crossing the threshold: 15 pts (C1a only).

## Verification strategy

`export_result.sh` reads via XML-RPC:
- `hr.employee` — checks `parent_id` for Rachel Perry and Doris Cole
- `hr.expense.sheet` — checks `state` for the departing manager's seeded sheet
- `hr.employee` (with `active_test: False`) — checks `active`, `departure_reason_id`, `departure_date` for the departing manager
- `mail.message` — scans chatter messages on the employee record for leave/PTO/balance keywords

Ground truth written to `/tmp/departure_mgmt_gt.json` by setup.

## Data notes

Uses Odoo demo employee Tina Williamson (Management) as the departing manager. Setup sets Rachel Perry and Doris Cole's `parent_id` to Tina, and creates a submitted expense sheet in her name. On each run setup reactivates Tina and clears departure fields to ensure a clean starting state.

## Edge cases

- In Odoo 17, archiving an employee via the UI triggers a departure wizard that sets `departure_reason_id` and `departure_date`; a direct `active=False` write skips this.
- The chatter note check is keyword-based (case-insensitive: leave, pto, paid time, balance, vacation, days remaining) — the agent must log a real note, not just archive the record.
- `hr.applicant` and `hr.employee` archive behaviour differs; only `hr.employee` has the departure wizard.
