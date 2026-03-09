# Task: update_operator_authorizations

## Overview

A drone operator's compliance profile must be kept current as their business evolves.
This task requires updating the existing "Electric Inspection" operator record in the
Aerobridge fleet management system to reflect expanded operational capabilities and
correct regulatory classification.

## Goal

Update the **Electric Inspection** operator record with three independent changes:

1. **Add "videotaping" to Authorized Activities** — Electric Inspection is adding aerial
   video services to its offering. The operator currently only has "photographing".
2. **Add "SORA" to Operational Authorizations** — The company has completed the SORA
   (Specific Operations Risk Assessment) standard authorization in addition to their
   existing "SORA V2".
3. **Change Operator Type from "NA" to "Non-LUC"** — The regulatory classification must
   be updated; the company does not hold a Light UAS Operator Certificate.

## Data

- **Application**: Aerobridge admin panel at `http://localhost:8000/admin/`
- **Login**: `admin` / `adminpass123`
- **Target**: Operator "Electric Inspection" (company of same name)
- **Existing activities on Electric Inspection**: `photographing` only
- **Existing authorizations on Electric Inspection**: `SORA V2` only
- **Existing operator_type**: `NA` (0)

## Starting State

- Electric Inspection operator has `authorized_activities = [photographing]`
- Electric Inspection operator has `operational_authorizations = [SORA V2]`
- Electric Inspection operator has `operator_type = NA (0)`

## Success Criteria

All three changes must be saved to the Electric Inspection operator record:

| Criterion | Points | What is checked |
|-----------|--------|-----------------|
| `videotaping` in authorized_activities | 25 | `operator.authorized_activities` M2M set |
| `SORA` in operational_authorizations | 25 | `operator.operational_authorizations` M2M set |
| `operator_type == Non-LUC (2)` | 30 | `operator.operator_type == 2` |
| Changes done after task start | 20 | file timestamps / task start time check |
| **Total** | **100** | Pass threshold: **50** |

## Verification Approach

The `export_result.sh` script queries the Django ORM to read the current state of
the Electric Inspection operator record: its `authorized_activities` M2M set,
`operational_authorizations` M2M set, and `operator_type` integer field. The result
is saved as JSON. The verifier reads that JSON and checks each criterion.

Anti-gaming: The setup script resets Electric Inspection to the known baseline state
before the task starts. Wrong-target: the verifier checks the operator ID matches
Electric Inspection to reject changes made to a different operator.

## Notes

- The admin section for operators is under **Registry > Operators**
- Authorized Activities and Operational Authorizations are multi-select (M2M) fields
- The available activities are "photographing" and "videotaping"
- The available authorizations are "SORA" and "SORA V2"
- Operator Type dropdown: NA, LUC, Non-LUC, AUTH, DEC
