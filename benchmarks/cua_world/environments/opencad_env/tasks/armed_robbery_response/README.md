# Task: armed_robbery_response

## Domain Context

Senior police dispatchers coordinate multi-agency responses to violent crimes in progress. An armed robbery requires simultaneous creation of a CAD incident call, issuance of vehicle and person BOLOs for suspects, and entry of a warrant for an identified co-conspirator. This reflects real dispatcher responsibilities during complex criminal incidents requiring coordination across multiple CAD modules.

**Profession**: Senior Police Dispatcher
**Difficulty**: very_hard
**Occupation reference**: Police Dispatchers / Emergency Communications Officers

## Goal

An armed robbery is in progress at Vinewood Boulevard near Hawick Avenue. The agent must complete four independent documentation tasks:

1. **Create a 10-31 armed robbery call** at Vinewood Boulevard and Hawick Avenue with a narrative
2. **Issue a vehicle BOLO** for the blue Karin Kuruma with plate RPZ-7851
3. **File a person BOLO** for the Hispanic male suspect (brown leather jacket)
4. **Add a warrant** for Trevor Philips for "Armed Robbery" (issuing agency: Blaine County Sheriff Office)

## Success Criteria

| Criterion | Points | Notes |
|-----------|--------|-------|
| Call type is 10-31 (Crime in Progress) | 10 | Substring match |
| Street 1 contains "Vinewood Boulevard" | 5 | |
| Street 2 contains "Hawick Avenue" | 5 | |
| Vehicle BOLO created | 10 | |
| Vehicle BOLO plate contains "RPZ-7851" | 15 | Normalized: dash-stripped comparison |
| Person BOLO created | 10 | |
| Person BOLO description has relevant keywords | 10 | hispanic, brown, jacket, leather, robbery, etc. |
| Warrant for Trevor Philips (name_id=3) | 20 | Wrong-target gate: other person → 0 for warrant section |
| Warrant name contains "robbery" / "armed" | 15 | Partial match: 8 pts |

**Pass threshold**: 70 / 100
**Do-nothing score**: 0 (gated on call_found)

## Database Schema

### ncic_warrants
- `id`, `expiration_date`, `warrant_name`, `issuing_agency`, `name_id` → FK to ncic_names.id, `issued_date`, `status`

### bolos_vehicles
- `id`, `vehicle_make`, `vehicle_model`, `vehicle_plate`, `primary_color`, `secondary_color`, `reason_wanted`, `last_seen`

### bolos_persons
- `id`, `first_name`, `last_name`, `gender`, `physical_description`, `reason_wanted`, `last_seen`

### ncic_names
- Trevor Philips: id=3 (existing seed data — already has 2 warrants for other offenses)

## Verification Strategy

- **Baseline**: Max IDs recorded for calls, bolos_vehicles, bolos_persons, ncic_warrants
- **Wrong-target gate**: If a warrant is found but NOT for name_id=3 (Trevor Philips), warrant score = 0
- **Gate**: No call found → total score = 0
- **Export**: `export_result.sh` writes `/tmp/armed_robbery_response_result.json`

## Seed Data Used

- Trevor Philips (ncic_names id=3): existing record with 2 prior warrants
- Streets Vinewood Boulevard + Hawick Avenue: confirmed in call_history seed data
- New vehicle BOLO plate RPZ-7851: scenario-specific plate (not pre-existing)

## Edge Cases

- Trevor already has warrants from seed — verifier uses id > baseline to find only NEW warrants
- Vehicle plate may be entered with or without hyphen — verifier strips hyphens for comparison
- Agent may use 10-30 or other crime-in-progress code — verifier accepts "10-31" or "crime in progress" or "armed robbery" in call type
