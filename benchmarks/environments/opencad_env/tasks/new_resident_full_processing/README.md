# Task: new_resident_full_processing

## Domain Context

NCIC Records Technicians at law enforcement records bureaus process new subject registrations that require creating multiple cross-linked records: a civilian identity, a registered vehicle tied to that identity, and a warrant linked to the same person. This workflow requires navigating multiple distinct modules of the CAD system and correctly linking records by identity ID — a realistic and complex multi-step records management task.

**Profession**: NCIC Records Technician
**Difficulty**: very_hard
**Occupation reference**: Police Records Clerks / Law Enforcement Records Technicians

## Goal

A new subject — Lamar Davis — requires full NCIC processing. The agent must:

1. **Register Lamar Davis as a new civilian identity** with: DOB 1988-09-05, address 1432 Forum Drive Davis Los Santos, Male, Black or African American, DL Valid
2. **Register his vehicle** (Bravado Baller, plate LAM-8844, white, Los Santos) **linked to his NCIC record**
3. **Add an active warrant** for Lamar Davis for "Receiving Stolen Property" issued by the Blaine County Sheriff Office

All three records must reference the same Lamar Davis identity. The warrant and vehicle must be linked to the newly created civilian ID.

## Success Criteria

| Criterion | Points | Notes |
|-----------|--------|-------|
| New civilian named "Lamar Davis" found | 15 | Wrong-target gate: wrong name → score=0 |
| DOB matches 1988-09-05 | 7 | Flexible matching: year+month+day present |
| Gender matches "Male" | 3 | Case-insensitive |
| Vehicle registration found | 10 | |
| Plate contains "LAM" and "8844" | 15 | Dash-normalized |
| Vehicle linked to Lamar Davis (name_id matches) | 10 | |
| Warrant found | 15 | |
| Warrant name contains "stolen property" or "receiving" | 15 | Partial: 8 pts |
| Issuing agency contains "blaine" or "sheriff" | 10 | |

**Pass threshold**: 70 / 100
**Do-nothing score**: 0 (gated on civilian found + name match)

## Database Schema

### ncic_names (civilian identities)
- `id`, `submittedByName`, `submittedById`, `name` (single full-name field), `dob`, `address`, `gender`, `race`, `dl_status`, `hair_color`, `build`, `weapon_permit`, `deceased`
- Existing records: IDs 1-4 (Michael, Franklin, Trevor, Amanda)

### ncic_plates (vehicle registrations)
- `id`, `name_id` → FK to ncic_names.id, `veh_plate`, `veh_make`, `veh_model`, `veh_pcolor`, `veh_scolor`, `veh_insurance`, `veh_insurance_type`, `flags`, `veh_reg_state`, `notes`, `user_id`

### ncic_warrants
- `id`, `expiration_date`, `warrant_name`, `issuing_agency`, `name_id`, `issued_date`, `status`

## Verification Strategy

- **Baseline**: Max IDs recorded for ncic_names, ncic_plates, ncic_warrants
- **Wrong-target gate (outer)**: No new civilian → score=0 (gate)
- **Wrong-target gate (inner)**: New civilian found but name ≠ "Lamar Davis" → score=0
- **Linkage check**: Vehicle's name_id must equal the new civilian's id
- **Warrant linkage**: Export first searches for warrant with name_id=new_civilian_id, then falls back to any new warrant
- **Export**: `export_result.sh` writes `/tmp/new_resident_full_processing_result.json`

## Subject Data (GTA V Character)

Lamar Davis is a canonical GTA V character. Data:
- Full name: Lamar Davis
- DOB: 1988-09-05 (age-consistent with GTA V storyline)
- Address: 1432 Forum Drive, Davis, Los Santos (Lamar's neighborhood in GTA V)
- Gender: Male
- Race: Black or African American
- DL Status: Valid (for task setup; warrant is for other offense)
- Vehicle: Bravado Baller (Lamar drives this in GTA V), plate LAM-8844

## Edge Cases

- Agent must create civilian FIRST before linking vehicle/warrant to that ID
- The civilian ID assigned will be > 4 (seed has IDs 1-4); verifier queries by id > baseline
- Plate may be entered as "LAM-8844" or "LAM8844" — verifier normalizes both
- Warrant linkage: verifier first checks new warrants with name_id = new_civilian_id
