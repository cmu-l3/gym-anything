# Task: multi_jurisdiction_pursuit

## Domain Context

Communications Center Supervisors manage multi-jurisdiction incidents that require coordinating documentation across all CAD modules simultaneously. A high-speed pursuit crossing county lines requires: a pursuit call, vehicle BOLO for the suspect vehicle, a new felony warrant for the driver, and a reckless driving citation. This is among the most complex dispatcher documentation scenarios, requiring proficiency with all major CAD system features.

**Profession**: Communications Center Supervisor
**Difficulty**: very_hard
**Occupation reference**: Emergency Communications Center Supervisors / PSAP Supervisors

## Goal

A multi-jurisdiction vehicle pursuit is in progress near Del Perro Boulevard, involving Trevor Philips in a red Pegassi Infernus (plate BLC-4491). The agent must complete four documentation tasks:

1. **Create a 10-80 vehicle pursuit call** at Del Perro Boulevard with a detailed narrative
2. **Issue a vehicle BOLO** for the red Pegassi Infernus with plate BLC-4491
3. **Add a warrant** for Trevor Philips for "Evading Police Officer - Felony" (issuing agency: San Andreas Highway Patrol)
4. **Issue a citation** to Trevor Philips for "Reckless Driving" — fine: $750.00

All four records must be created and linked to the correct persons/vehicles.

## Success Criteria

| Criterion | Points | Notes |
|-----------|--------|-------|
| Call type is 10-80 (Pursuit) | 10 | Accepts "pursuit", "chase", "10-80" |
| Street 1 contains "Del Perro Boulevard" | 5 | "del perro" or "perro" accepted |
| Vehicle BOLO created | 10 | |
| Plate contains "BLC" and "4491" | 10 | Partial: 5 pts for BLC alone |
| Warrant for Trevor Philips (name_id=3) | 15 | Wrong-target gate: other person → 0 for warrant section |
| Warrant name contains "evad" or "felony/pursuit/flee" | 15 | Partial: 8 pts |
| Citation for Trevor Philips (name_id=3) | 15 | Wrong-target gate: other person → 0 for citation section |
| Citation name contains "reckless" | 15 | Partial: 8 pts |
| Citation fine matches $750.00 | 5 | ±$75 for partial |

**Pass threshold**: 70 / 100
**Do-nothing score**: 0 (gated on call_found)

## Database Schema

### ncic_names
- Trevor Philips: id=3 (existing — already has 2 warrants, 1 citation from seed data)

### ncic_warrants
- `id`, `expiration_date`, `warrant_name`, `issuing_agency`, `name_id`, `issued_date`, `status`
- Trevor existing warrants: ids 1, 2 — baseline captures these, only new warrants (id > baseline) counted

### ncic_citations
- Trevor existing citation: id=1 (Speeding, $250) — baseline captures this

### bolos_vehicles
- `id`, `vehicle_make`, `vehicle_model`, `vehicle_plate`, `primary_color`, `secondary_color`, `reason_wanted`, `last_seen`

## Verification Strategy

- **Baseline**: Max IDs for calls, bolos_vehicles, ncic_warrants, ncic_citations (critical: Trevor has pre-existing records)
- **Wrong-target gate (warrant)**: New warrant found but NOT name_id=3 → warrant score=0
- **Wrong-target gate (citation)**: New citation found but NOT name_id=3 → citation score=0
- **Gate**: No new call found → total score=0
- **Export search**: Prioritizes Trevor's new records in export; falls back to any new record
- **Export**: `export_result.sh` writes `/tmp/multi_jurisdiction_pursuit_result.json`

## Seed Data Used

- Trevor Philips (ncic_names id=3): existing with prior warrants and citation
- Del Perro Boulevard: confirmed in call_history seed data (call_id=5)
- New vehicle plate BLC-4491: scenario-specific (not pre-existing)

## Edge Cases

- **Pre-existing Trevor records**: Critical — baselines MUST be set before task to avoid false positives on Trevor's 2 existing warrants and 1 existing citation
- Plate entry with or without hyphen — verifier normalizes
- Agent may complete subtasks in any order; all are independent
- Export script searches for Trevor-specific new warrant/citation first; if agent created records for wrong person, those are also detected and reported
