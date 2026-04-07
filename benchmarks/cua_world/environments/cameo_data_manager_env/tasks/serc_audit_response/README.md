# Task: SERC Audit Response

## Overview

A multi-issue data quality correction task requiring the agent to read an external audit report and make four independent corrections to a facility's Tier II data in CAMEO. Mirrors the real compliance workflow of responding to a regulatory audit with data corrections.

**Difficulty**: Very Hard
**Domain**: EPCRA compliance / regulatory data quality
**Real workflow**: After a SERC physical inspection, facilities receive written audit findings identifying specific data errors. The compliance officer must correct all findings in CAMEO and submit a corrected Tier II export to the SERC office.

## Goal

All four SERC audit findings for Lakeside Chemical Supply must be corrected in CAMEO and the dataset exported as XML.

End state: `C:\Users\Docker\Documents\CAMEO\lakeside_corrected.xml` contains all four corrections applied.

## Task Description

1. Import `C:\workspace\data\lakeside_chemical.xml` into CAMEO
2. Read the audit report at `C:\workspace\data\serc_audit_report.txt`
3. Make all four corrections identified in the report
4. Export corrected data to `C:\Users\Docker\Documents\CAMEO\lakeside_corrected.xml`

## What the Audit Report Says (Four Findings)

| Finding | Issue | Correction |
|---------|-------|------------|
| #1 | Hydrogen Peroxide average 8,500 lbs exceeds tank capacity of 4,200 lbs | Set average to 4,200 lbs |
| #2 | Sulfuric Acid stored in "Chemical Storage A" but actually in "Drum Storage Building B" | Update storage location |
| #3 | David Nguyen's phone disconnected; replacement: Patricia Okonkwo, 802-555-0293 | Replace contact |
| #4 | Fire district "Station 4 - Montpelier South" is incorrect | Set to "Station 12 - Montpelier Central" |

## Verification Strategy

The verifier parses the exported XML for all four corrections.

### Scoring (100 points)

| Criterion | Points | Check |
|-----------|--------|-------|
| H2O2 average corrected to ≤5,000 lbs | 25 | aveAmountCode="04" OR aveAmount ≤ 5,000 |
| Sulfuric Acid storage = "Drum Storage Building B" | 25 | storageLocation contains "Drum Storage Building B" |
| Patricia Okonkwo added as Fac. Emergency Coordinator | 25 | Contact "Okonkwo" with Fac. Emergency Coordinator type |
| Fire district = "Station 12 - Montpelier Central" | 25 | fireDistrict contains "Station 12" or "Montpelier Central" |

**Pass threshold**: ≥ 70 points
**Wrong-target gate**: Score = 0 if export doesn't contain "Lakeside Chemical Supply"

## Why This Is Very Hard

- The agent must read and interpret an external text document (the audit report)
- Four independent subtasks span different areas of the CAMEO UI (chemical records, contacts, facility info)
- The agent cannot rely on the task description for specific field values — all information comes from the audit report
- The fire district field is in the facility record, not the chemical record — the agent must find it
