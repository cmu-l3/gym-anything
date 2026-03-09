# Task: bpmn_procurement_compliance

**ID**: bpmn_procurement_compliance@1
**Difficulty**: very_hard
**Occupation**: Management Analysts ($1.03B GDP impact) + Business Continuity Planners ($1.11B GDP)
**Timeout**: 900 seconds | **Max Steps**: 100

## Domain Context

Management analysts and business process professionals use BPMN 2.0 (Business Process Model and Notation, ISO/IEC 19510:2013) as the standard language for documenting organizational workflows. Non-compliant BPMN diagrams are rejected during process governance audits. Correcting violations requires deep knowledge of BPMN element types (gateways, events, tasks, data objects), swimlane semantics, and sequence flow labeling rules.

## Task Goal

Open a non-compliant BPMN procurement diagram (`~/Diagrams/procurement_process.drawio`) and correct all 5+ BPMN 2.0 violations documented in `~/Desktop/bpmn_audit_checklist.txt`. The corrected diagram must have proper swimlane lanes for all organizational roles, correctly typed gateways, labeled gateway exit flows, a rejection path, and proper data objects. Export to PDF and PNG.

## What Makes This Hard

1. **Violation discovery**: Not told WHERE violations are — must read and interpret the diagram vs. BPMN standard
2. **BPMN knowledge required**: Must know gateway types (exclusive vs. parallel), event types, task types, swimlane semantics
3. **Structural changes**: Must restructure swimlanes (splitting 1 lane into 4) — significant UI work in draw.io
4. **Multiple independent subtasks**: 6 distinct violations each requiring different fixes
5. **BPMN shape library**: Must use draw.io's BPMN shape library for correct element types

## Planted Violations

| # | Violation | Fix Required |
|---|-----------|-------------|
| 1 | Single swimlane (Procurement only) | Add Requester, Budget Owner, Finance lanes |
| 2 | Unnamed start event | Add meaningful start event label |
| 3 | Parallel gateway for exclusive decision | Change to Exclusive (XOR) gateway |
| 4 | Unlabeled gateway exit flows | Add "Approved" / "Rejected" labels |
| 5 | Missing rejection path | Add notification task + rejection end event |
| 6 | Intermediate throw event for PO send | Replace with Send Task |

## Success Criteria

| Criterion | Points |
|-----------|--------|
| File modified after task start | 10 |
| ≥3 swimlane lanes (was 1) | 20 |
| Exclusive (XOR) gateway present | 15 |
| Gateway exit flows labeled | 15 |
| Named start event | 10 |
| Rejection path present | 10 |
| PDF exported | 10 |
| PNG exported | 10 |

**Pass threshold**: 60 points

## Starting State

- `~/Diagrams/procurement_process.drawio`: Broken BPMN with 5+ compliance violations
- `~/Desktop/bpmn_audit_checklist.txt`: Detailed compliance requirements and violation descriptions
