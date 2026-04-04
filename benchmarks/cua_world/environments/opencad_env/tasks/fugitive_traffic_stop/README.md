# Task: fugitive_traffic_stop

## Domain Context

Police dispatchers at a Communications Center (PSAP) are responsible for multi-step documentation during rapidly evolving incidents. A traffic stop that escalates — with a suspect fleeing — requires simultaneous creation of a CAD call, issuance of a citation to the driver, and filing of a person BOLO for the fugitive. This mirrors real law enforcement dispatcher workflows under time pressure.

**Profession**: Police Dispatcher
**Difficulty**: very_hard
**Occupation reference**: Law Enforcement Dispatchers / Public Safety Telecommunicators

## Goal

A traffic stop at Forum Drive and Strawberry Avenue has escalated. The agent must complete three independent documentation tasks using the OpenCAD system:

1. **Create a 10-38 traffic stop call** at Forum Drive and Strawberry Avenue with a narrative
2. **Issue a citation** to Franklin Clinton (the vehicle operator) for "Running Red Light" — fine: $175.00
3. **Create a person BOLO** for the fleeing passenger (Black male, athletic build, gray hoodie)

All three records must be created. Partial completion results in partial credit.

## Success Criteria

| Criterion | Points | Notes |
|-----------|--------|-------|
| Call type is 10-38 (Traffic Stop) | 15 | Case-insensitive substring match |
| Street 1 contains "Forum Drive" | 10 | |
| Street 2 contains "Strawberry Avenue" | 10 | |
| Citation exists for Franklin Clinton (name_id=2) | 10 | Wrong-target gate: any other person → 0 for citation section |
| Citation name contains "Red Light" | 20 | Partial match accepted |
| Citation fine matches $175.00 | 15 | ±$25 for close match |
| Person BOLO created | 10 | |
| BOLO description has relevant keywords | 10 | gray, hoodie, black, fled, athletic, etc. |

**Pass threshold**: 70 / 100
**Do-nothing score**: 0 (gated on call_found)

## Database Schema

### ncic_names (person registry)
- `id`, `name` (single full-name field), `dob`, `address`, `gender`, `race`, `dl_status`
- Franklin Clinton: id=2, name="Franklin Clinton"

### ncic_citations
- `id`, `status`, `name_id` → FK to ncic_names.id, `citation_name`, `citation_fine`, `issued_date`, `issued_by`

### bolos_persons
- `id`, `first_name`, `last_name`, `gender`, `physical_description`, `reason_wanted`, `last_seen`

### calls / call_history
- `call_id`, `call_type`, `call_primary`, `call_street1`, `call_street2`, `call_street3`, `call_narrative`

## Verification Strategy

- **Baseline**: Max IDs recorded at setup for calls (active+history), citations, and bolos_persons
- **Wrong-target gate**: If a citation is found for anyone other than name_id=2 (Franklin Clinton), citation score = 0
- **Gate**: If no new call found → total score = 0
- **Export**: `export_result.sh` writes `/tmp/fugitive_traffic_stop_result.json`

## Seed Data Used

- Franklin Clinton (ncic_names id=2): existing record from seed_data.sql
- Vehicle plate 63JIG803: existing Bravado Buffalo registered to Franklin
- Streets Forum Drive + Strawberry Avenue: confirmed in call_history seed data

## Edge Cases

- Agent may close the call before export — verifier checks both `calls` and `call_history` tables
- Citation fine may be entered as "175" or "175.00" — verifier accepts float comparison within ±$25
- BOLO first/last name fields may vary; verifier checks `physical_description` and `reason_wanted` for keywords
