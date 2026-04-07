# Task: Chemical Inventory Update

## Overview

An annual inventory update task requiring the agent to modify existing chemical quantities and add a new chemical to an existing facility record. Mirrors the real workflow of updating CAMEO before the Tier II filing deadline.

**Difficulty**: Hard
**Domain**: EPCRA Tier II compliance / facility chemical inventory management
**Real workflow**: Facility managers update CAMEO annually with final inventory figures before submitting the Tier II report to the SERC and LEPC.

## Goal

Three specific changes to Green Valley Water Facility must be made and the dataset exported as XML.

End state: `C:\Users\Docker\Documents\CAMEO\green_valley_2024.xml` contains updated inventory with Chlorine max=60,000 lbs, Fluorosilic Acid average=55,000 lbs, and new Sodium Hypochlorite chemical record.

## Task Description

Green Valley Water Facility is already imported. Make these updates:

1. **Chlorine** (CAS 7782-50-5): Update maximum daily amount from 20,000 to 60,000 lbs
2. **Fluorosilic Acid** (CAS 16961-83-4): Update average daily amount from 20,000 to 55,000 lbs
3. **Add Sodium Hypochlorite** (CAS 7681-52-9): liquid, non-EHS, average 8,500 lbs, maximum 15,000 lbs, storage location "Chemical Injection Room", type "Above ground tank"

Export to `C:\Users\Docker\Documents\CAMEO\green_valley_2024.xml`.

## Verification Strategy

The verifier parses the exported XML for updated amount codes and the new chemical.

### Scoring (100 points)

| Criterion | Points | Check |
|-----------|--------|-------|
| Chlorine max in 50k-99.9k range | 25 | maxAmountCode="07" OR maxAmount ≥ 50,000 |
| Fluorosilic Acid average in 50k-99.9k range | 25 | aveAmountCode="07" OR aveAmount ≥ 50,000 |
| Sodium Hypochlorite (7681-52-9) present | 25 | Chemical with CAS 7681-52-9 exists in XML |
| NaOCl storage location = Chemical Injection Room | 25 | storageLocation contains "Chemical Injection Room" |

**Pass threshold**: ≥ 70 points
**Wrong-target gate**: Score = 0 if export doesn't contain Green Valley Water Facility

## Notes

- Amount codes: 06=10k-49.9k, 07=50k-99.9k. Both Chlorine (20k→60k) and Fluorosilic Acid (20k→55k) cross from code 06 to 07.
- The agent must locate the facility in the Facilities module, open each chemical record, and edit the quantity fields.
- Adding a new chemical requires using the "New Chemical" or "Add Chemical" functionality in CAMEO.
