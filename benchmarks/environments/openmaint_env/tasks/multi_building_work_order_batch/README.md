# Multi-Building Work Order Batch

## Domain Context

After a severe weather event, regional maintenance directors must rapidly create
emergency work orders across multiple buildings, prioritize them by severity,
and close any pre-existing tickets that were already resolved. This requires
coordinating across buildings, applying correct priority classifications,
and distinguishing storm-related work from unrelated ongoing campaigns.

**Occupation:** Maintenance and Repair Workers, General (SOC 49-9071.00)
**Industry:** Commercial Property Management

## Goal

Process storm damage across three buildings by creating and managing work orders.
The agent must:
1. Create three new corrective maintenance work orders (one per building) with
   specific codes, descriptions, and priorities matching the severity of each
   building's damage
2. Assign each work order to the correct building
3. Set priorities: critical (roof breach with water intrusion), high (HVAC unit
   displacement), medium (parking garage lighting failure)
4. Close the pre-existing work order WO-PRE-RESOLVED (minor issue already fixed)
5. Preserve work order WO-CONTAM-001 unchanged (quarterly fire extinguisher
   campaign — unrelated to storm damage)

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| C1 Created | 25 | 3 storm work orders created (matched by code or description keywords) |
| C2 Buildings | 20 | Each WO assigned to the correct building |
| C3 Priorities | 20 | Priorities match expected severity (critical/high/medium) |
| C4 Closure | 20 | Pre-resolved WO closed/completed |
| C5 Contamination | 15 | WO-CONTAM-001 preserved unchanged |

**Pass threshold:** 60/100
**Score cap:** If contamination WO is deleted/deactivated, score capped at 50.

## Verification Strategy

- **Setup** creates WO-PRE-RESOLVED and WO-CONTAM-001, records their IDs and
  initial state. Records baseline WO count and all existing WO IDs.
  Places storm damage report on desktop.
- **Export** searches for new WOs by expected code or description keywords,
  checks pre-resolved WO status, and compares contamination WO to its
  initial state.
- **Verifier** scores each criterion. Do-nothing detection: if no new WOs
  created and pre-resolved WO not closed, score = 0.

## Schema Reference

- **Class:** CorrectiveMaint (process class) or WorkOrder/Ticket (card class)
- **Key fields:** Code, Description, Priority (lookup), Building (reference),
  Status, _is_active
- **Baseline file:** `/tmp/wob_baseline.json`
- **Result file:** `/tmp/wob_result.json`

## Expected Work Orders

| Code | Building | Priority | Damage Description |
|------|----------|----------|--------------------|
| WO-STORM-001 | Building 1 | Critical | Roof membrane breach, water intrusion into electrical room |
| WO-STORM-002 | Building 2 | High | HVAC rooftop unit displaced, condenser fan cracked |
| WO-STORM-003 | Building 3 | Medium | Parking garage lighting circuit failure |

## Task Input File

`/home/ga/Desktop/storm_damage_report.txt` contains the damage assessment with
building-by-building damage descriptions, priorities, and work order codes.

## Edge Cases

- WO-CONTAM-001 is about fire extinguisher inspection and could be confused with
  storm-related safety work. Agent must read the description to determine it is
  unrelated to storm damage.
- Agent may attempt to close WO-CONTAM-001 along with WO-PRE-RESOLVED.
  Verifier checks that its description and active status are unchanged.
- Work order matching uses both exact code match and keyword fallback
  (for agents that use different codes but correct content).
