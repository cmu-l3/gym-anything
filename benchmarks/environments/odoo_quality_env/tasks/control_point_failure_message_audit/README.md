# control_point_failure_message_audit

## Domain Context

**Occupation**: Process Validation Engineer
**Industry**: Office Equipment Manufacturing / Regulated Manufacturing
**Software**: Odoo 17 Quality Module (Quality Control Points)
**Difficulty**: very_hard

Process Validation Engineers preparing for FDA 21 CFR Part 820 or ISO 9001 compliance reviews must ensure all Quality Control Points (QCPs) have configured failure messages — mandatory inspector guidance for non-conforming results. Engineers must also identify gaps in inspection protocol coverage and create new QCPs for product areas not yet covered.

## Task Description

Pre-compliance review found that several QCPs lack failure messages (non-compliant). The agent must:

1. **Add failure messages** to every Quality Control Point that currently has no failure message
2. **Create a new Measure-type QCP** for the "Customizable Desk" product covering the height adjustment mechanism (force measurement), with a failure message

The agent must navigate to Quality > Control Points, identify which QCPs lack failure messages by reviewing each one, fill in appropriate messages, and then create a new QCP with the correct test type and product association.

## Starting State

`setup_task.sh`:
- Pre-fills failure_message on "Final Assembly Audit" and "Chair Stability Load Test" (2 already done)
- Clears failure_message from 3 target QCPs: "Incoming Parts Verification", "Screen Dimensional Inspection", "Desk Surface Flatness Check"
- Removes any prior "Desk Height" or "Height Adjustment" QCPs (idempotent)

The 5 QCPs in the system after setup:
- **Final Assembly Audit** — has failure message (pre-filled) ✓
- **Chair Stability Load Test** — has failure message (pre-filled) ✓
- **Incoming Parts Verification** — NO failure message ← agent must fix
- **Screen Dimensional Inspection** — NO failure message ← agent must fix
- **Desk Surface Flatness Check** — NO failure message ← agent must fix
- *(New)* Desk height adjustment QCP must be CREATED by agent

## Verification Strategy

**Multi-criterion scoring (100 pts total, pass ≥ 60):**

| Criterion | Points | Condition |
|-----------|--------|-----------|
| C1: All 3 QCPs have failure messages | 40 pts | All 3 targets have failure_message ≥ 10 chars |
| C1 partial (2/3) | 27 pts | 2 of 3 targets filled |
| C1 partial (1/3) | 13 pts | 1 of 3 targets filled |
| C2: New Measure QCP exists | 35 pts | New QCP with test_type='measure' for Desk exists |
| C2 partial (wrong type) | 15 pts | New QCP found but wrong test type |
| C3: New QCP has failure message | 25 pts | New QCP has failure_message ≥ 10 chars |

**Partial credit check**: Max partial = 13 (1 QCP) + 15 (wrong type) + 0 = 28 < 60. Pass requires at least 2/3 QCPs (27) + new QCP with message (25+35=60) or all 3 QCPs (40) + new QCP found (15+25=40) = 80. ✓

## Schema Reference

- **Model**: `quality.point`
- **Fields**: `name`, `failure_message` (Html or text), `test_type` (selection: 'instructions'/'passfail'/'measure'/'picture'), `product_ids` (Many2many → product.product)
- **Target product**: "Customizable Desk" (product.product)
- **New QCP test_type**: 'measure'

## Files

- `task.json` — task configuration and hooks
- `setup_task.sh` — pre-fills 2 QCPs, clears 3 target QCPs, removes stale new QCPs
- `export_result.sh` — checks failure_message on 3 targets, searches for new Measure QCP
- `verifier.py` — multi-criterion scoring

## Edge Cases

- New QCP may not be linked to Desk product (agent forgot): export searches by test_type AND name keywords ("desk", "height") as fallback
- Agent may create QCP with passfail type instead of measure: partial credit (15 pts for C2)
- Agent may add failure messages with HTML tags: export strips HTML before length check
