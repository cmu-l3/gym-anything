# Task: major_incident_documentation

## Domain Context

Incident Commanders and Senior Dispatchers at large Communications Centers manage complex multi-agency incidents involving fire, hazmat, and law enforcement simultaneously. Documentation of a major industrial incident requires: creating a high-priority fire/hazmat CAD call, issuing a regulatory citation to a responsible party, and filing a person BOLO for a fleeing person of interest. This reflects real Incident Commander responsibilities during HAZMAT events.

**Profession**: Incident Commander / Senior Dispatcher
**Difficulty**: very_hard
**Occupation reference**: Emergency Management Directors / Senior Public Safety Dispatchers

## Goal

An explosion and structural fire with HAZMAT involvement has occurred at an industrial facility on El Rancho Boulevard near Jamestown Street. The agent must complete three documentation tasks:

1. **Create a 10-70 structure fire call** at El Rancho Boulevard and Jamestown Street with a narrative covering the HAZMAT concerns
2. **Issue a citation to Michael De Santa** (facility operations manager) for "Safety Violation" — fine: $2,500.00
3. **Create a person BOLO** for a fleeing white male suspect (heavyset, bald, blue work jacket)

## Success Criteria

| Criterion | Points | Notes |
|-----------|--------|-------|
| Call type is 10-70 (Structure Fire) | 15 | Accepts "fire" or "10-70" in call type |
| Street 1 contains "El Rancho Boulevard" | 10 | "rancho" accepted |
| Street 2 contains "Jamestown Street" | 5 | |
| Citation exists for Michael De Santa (name_id=1) | 10 | Wrong-target gate: other person → 0 for citation section |
| Citation name contains "Safety Violation" | 20 | Partial ("safety" OR "violation"): 10 pts |
| Citation fine matches $2,500.00 | 15 | ±$250 for close match |
| Person BOLO created | 15 | |
| BOLO description has relevant keywords | 10 | white, bald, heavyset, blue, jacket, fled, etc. |

**Pass threshold**: 70 / 100
**Do-nothing score**: 0 (gated on call_found)

## Database Schema

### ncic_names
- Michael De Santa: id=1 (existing seed record)

### ncic_citations
- `id`, `status`, `name_id` → FK to ncic_names.id, `citation_name`, `citation_fine`, `issued_date`, `issued_by`

### bolos_persons
- `id`, `first_name`, `last_name`, `gender`, `physical_description`, `reason_wanted`, `last_seen`

### calls / call_history
- `call_id`, `call_type`, `call_primary`, `call_street1`, `call_street2`, `call_street3`, `call_narrative`

## Verification Strategy

- **Baseline**: Max IDs for calls (active+history), citations, bolos_persons
- **Wrong-target gate**: Citation found but NOT for name_id=1 (Michael De Santa) → citation score=0
- **Gate**: No new call found → total score=0
- **Fine tolerance**: ±$1.00 for exact match; ±$250 for partial credit
- **Export**: `export_result.sh` writes `/tmp/major_incident_documentation_result.json`

## Seed Data Used

- Michael De Santa (ncic_names id=1): existing record, no prior citations
- Streets El Rancho Boulevard + Jamestown Street: confirmed in call_history seed data (call_id=4)
- Citation fine $2,500 reflects realistic regulatory penalties for OSHA-type violations

## Edge Cases

- Fine $2,500 may be entered as 2500, 2500.00, or 2,500.00 — verifier uses float parsing
- Agent might create BOLO before or after the call — order doesn't matter
- Agent may close the call (moving it to call_history) — verifier checks both tables
- "Safety Violation" partial matches accepted: "safety" alone = 10 pts, full match = 20 pts
