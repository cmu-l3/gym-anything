# Task: cascade_emergency_response

## Domain
Occupational Health and Safety — HAZMAT Emergency Response

## Overview
An OHS Specialist is contacted by the county emergency manager following a freight rail derailment. Four tank cars carry hazardous chemicals, but the manifest lists ONLY UN numbers — not chemical names. Two adjacent cars (TC-101 and TC-102) have active leaks and are physically touching, with a visible white/yellowish vapor cloud forming between them. The agent must use CAMEO Chemicals to identify each chemical, determine the reaction occurring between TC-101 and TC-102, look up isolation distances, and provide an emergency response assessment including a shelter-in-place vs. evacuation recommendation for a nearby facility.

## Starting State
- Firefox is open at CAMEO Chemicals (https://cameochemicals.noaa.gov/)
- `~/Desktop/train_derailment_manifest.txt` contains the incident report with UN numbers only
- No output file exists at task start

## Goal / End State
Produce a written emergency response assessment at:
```
~/Documents/train_derailment_assessment.txt
```

The report must include:
1. Chemical identity for each car (TC-101 through TC-104), determined from UN numbers
2. Assessment of the TC-101/TC-102 chemical interaction and products
3. Isolation distances (large spill) for the leaking chemicals
4. Required PPE for first responders
5. Shelter-in-place vs. evacuation recommendation for the facility (0.7 miles away)
6. Priority order of response actions

## Chemicals (NOT revealed to the agent — must be discovered)

| Car | UN Number | Chemical |
|-----|-----------|---------|
| TC-101 | UN 1050 | Hydrogen Chloride (anhydrous, liquefied) |
| TC-102 | UN 1005 | Ammonia (anhydrous) |
| TC-103 | UN 2209 | Formaldehyde solution |
| TC-104 | UN 1791 | Hypochlorite solution |

**Key reaction**: TC-101 (HCl) + TC-102 (NH3) → Ammonium Chloride white aerosol cloud + highly toxic atmosphere

## Difficulty: very_hard

- UN numbers only — no chemical names in the manifest
- Must correctly identify all 4 chemicals using CAMEO UN number search
- Must assess what the mixing of HCl and NH3 produces (not obvious without looking it up)
- Isolation distances require CAMEO datasheet or Emergency Response Guide lookup
- Must make a defensible shelter-in-place vs. evacuation call given wind/distance data

## Verification Strategy

| Criterion | Points | Check |
|-----------|--------|-------|
| File gate | 0/100 | If no output file → score=0 |
| Chemical ID (4 × 5 pts) | 20 | Each chemical identified by name from UN number |
| TC-101/TC-102 reaction | 25 | HCl + NH3 reaction with cloud/product described |
| Isolation distances | 20 | Distance/zone mentioned |
| PPE requirements | 15 | SCBA/respirator/Level A/B mentioned |
| Shelter/evacuation rec. | 15-20 | Specific recommendation given |

Pass threshold: 60/100
