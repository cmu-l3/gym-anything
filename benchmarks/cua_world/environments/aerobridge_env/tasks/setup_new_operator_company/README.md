# Task: setup_new_operator_company

## Overview

Onboarding a new drone operator in Aerobridge requires two dependent records:
first a **Company** (the legal entity), then an **Operator** record linked to that
company with its regulatory authorizations and permitted activities. This task
requires understanding the relationship between Company and Operator models.

## Goal

Fully onboard a new drone services company:

1. **Create Company "BlueSky Robotics Pvt Ltd"** in Registry > Companies:
   - Full name: BlueSky Robotics Pvt Ltd
   - Common name: BlueSky
   - Role: Operator (role = 2)
   - Country: INDIA (IN)
   - Email: info@bluesky.in
   - Website: http://www.bluesky.in

2. **Create Operator record** in Registry > Operators, linked to the new company:
   - Company: BlueSky Robotics Pvt Ltd (common name "BlueSky" in dropdown)
   - Operator type: Non-LUC
   - Authorized Activities: add both "photographing" AND "videotaping"
   - Operational Authorizations: add "SORA"

## Data

- **Application**: Aerobridge admin panel at `http://localhost:8000/admin/`
- **Login**: `admin` / `adminpass123`
- **Company.role choices**: Supplier (0), Manufacturer (1), Operator (2), Customer (3), Assembler (4)
- **Operator type choices**: NA (0), LUC (1), Non-LUC (2), AUTH (3), DEC (4)
- **Available activities**: photographing, videotaping
- **Available authorizations**: SORA, SORA V2

## Starting State

- No company named "BlueSky Robotics Pvt Ltd" exists
- No operator linked to BlueSky exists

## Success Criteria

| Criterion | Points | What is checked |
|-----------|--------|-----------------|
| Company "BlueSky Robotics Pvt Ltd" exists | 15 | full_name match |
| Company has role=Operator (2) and country=IN | 15 | field values |
| Operator record linked to BlueSky company | 25 | `operator.company.full_name` |
| Operator has both activities | 25 | `authorized_activities` M2M set |
| Operator has SORA authorization | 20 | `operational_authorizations` M2M set |
| **Total** | **100** | Pass threshold: **60** |

## Verification Approach

`export_result.sh` queries the database for the new company and its linked operator,
reading M2M relationships. The verifier validates all fields.

Anti-gaming: setup records initial Company and Operator counts.
Wrong-target: verifier checks that the operator is linked to "BlueSky Robotics Pvt Ltd".

## Notes

- The Company dropdown in the Operator form shows `common_name`, so BlueSky will appear as "BlueSky"
- Company must be created FIRST — the operator form requires selecting an existing company
- Country field: only "INDIA" (IN) is available in the dropdown
- Role field: must be set to "Operator" for this company to show correctly in the operator context
