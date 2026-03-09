# Corrective Maintenance Triage

## Domain Context

Maintenance supervisors in commercial property management routinely receive batches
of corrective maintenance requests that were auto-classified by an intake system.
These requests often have incorrect priorities, wrong category assignments, and
unassigned technicians. The supervisor must triage each ticket by severity, fix
classifications, identify duplicates, and assign personnel.

**Occupation:** Maintenance and Repair Workers, General (SOC 49-9071.00)
**Industry:** Commercial Property Management

## Goal

Six new corrective maintenance tickets have been logged across three buildings.
The agent must:
1. Correct priority levels to match actual severity (gas leaks and fire code
   violations are critical; cosmetic issues are low)
2. Fix misclassified category/type fields (e.g., gas leak was filed as "plumbing")
3. Identify and close the duplicate ticket (two tickets describe paint peeling
   near an elevator, but one is a duplicate of an existing open ticket)
4. Assign all non-duplicate tickets to a technician from the existing personnel list
5. Preserve the legitimate paint-peeling ticket for a different building
   (contamination trap — similar description, different building, NOT a duplicate)

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| C1 Priority | 25 | 3 critical tickets (GAS_LEAK, EMERGENCY_LIGHT, HVAC_OVERHEAT) have priority set to critical/urgent |
| C2 Category | 20 | 3 misclassified tickets have corrected categories (gas→mechanical, window→structural, HVAC→mechanical) |
| C3 Duplicate | 20 | Duplicate ticket (CMT-2026-005) is closed/resolved |
| C4 Assignment | 20 | All 5 non-duplicate tickets have an assignee |
| C5 Contamination | 15 | Legitimate ticket (CMT-2026-006, different building) is NOT closed/deleted |

**Pass threshold:** 60/100
**Score cap:** If contamination ticket is wrongly deleted, score capped at 50.

## Verification Strategy

- **Setup** seeds 6 tickets via CMDBuild REST API with deliberately wrong priorities
  and categories. A 7th "original" ticket is created as the duplicate reference.
- **Export** reads current state of each seeded ticket via API (priority, category,
  status, assignee, active flag).
- **Verifier** checks each criterion against the exported state. Do-nothing detection:
  if no priorities changed, no tickets closed, and no assignees added, score = 0.

## Schema Reference

- **Class:** CorrectiveMaint (process class) or Ticket/WorkOrder (card class)
- **Key fields:** Priority (lookup), Category/Type (lookup), Status, Assignee, Building (reference)
- **Baseline file:** `/tmp/cmt_baseline.json`
- **Result file:** `/tmp/cmt_result.json`

## Seeded Tickets

| Code | Tag | Issue | Seeded Priority | Expected Priority | Category Error |
|------|-----|-------|-----------------|-------------------|----------------|
| CMT-2026-001 | GAS_LEAK | Gas leak in basement | low | critical | plumbing→mechanical |
| CMT-2026-002 | WINDOW_LATCH | Broken window latch | low | medium | electrical→structural |
| CMT-2026-003 | EMERGENCY_LIGHT | Emergency lighting failure | medium | critical | correct |
| CMT-2026-004 | HVAC_OVERHEAT | Server room HVAC failure | medium | critical | plumbing→mechanical |
| CMT-2026-005 | PAINT_PEEL_DUP | Paint peeling (duplicate) | low | low | correct (close as dup) |
| CMT-2026-006 | PAINT_PEEL_LEGIT | Paint peeling (different building) | low | low | correct (KEEP) |

## Edge Cases

- Agent may close CMT-2026-006 by mistake (similar description to duplicate).
  C5 contamination check catches this.
- Agent may delete tickets instead of closing them. Verifier accepts deletion
  for the duplicate (partial credit) but penalizes deletion of the contamination ticket.
- If corrective maintenance is a process class, status changes go through workflow
  activities rather than simple field updates.
