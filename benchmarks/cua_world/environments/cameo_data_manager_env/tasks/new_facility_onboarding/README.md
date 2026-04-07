# Task: New Facility Onboarding

## Overview

A comprehensive facility onboarding task requiring the agent to discover, import, configure, and verify two new facilities in CAMEO Data Manager. Each facility requires emergency contact and fire district assignments derived from information embedded in the facility records.

**Difficulty**: Very Hard
**Domain**: Corporate EHS management / EPCRA Tier II compliance
**Real workflow**: After a corporate acquisition, the EHS manager imports newly acquired facilities' Tier II data into the corporate CAMEO instance, then configures each facility with the correct local emergency contacts and fire district assignments needed for LEPC coordination.

## Goal

Both Champlain Plastics and Composites and Essex Chemical and Coatings must be fully onboarded with contacts and fire districts, and the dataset exported as XML.

End state: `C:\Users\Docker\Documents\CAMEO\new_facilities.xml` contains both facilities with correct fire districts and designated emergency contacts.

## Task Description

Two XML data files are available in `C:\workspace\data\`: `champlain_plastics.xml` and `essex_chemical.xml`. The agent must:

1. Import both XML files into CAMEO
2. For each facility, read the facility notes and certifier information to determine:
   - Who the designated emergency contact is (name, phone, contact type)
   - What fire district to assign
3. Add the contacts and assign fire districts
4. Export to `C:\Users\Docker\Documents\CAMEO\new_facilities.xml`

## What the Agent Must Discover from Facility Records

| Facility | Fire District (from notes) | Contact (from notes/certifier) | Contact Type |
|----------|---------------------------|-------------------------------|--------------|
| Champlain Plastics and Composites | Burlington Central Fire Station 3 | James Kowalski, 802-555-0451 | Fac. Emergency Coordinator |
| Essex Chemical and Coatings | Essex Fire District 1 | Sandra Obrecht, 802-555-0523 | Emergency Contact |

## Verification Strategy

### Scoring (100 points)

| Criterion | Points | Check |
|-----------|--------|-------|
| Both facilities present in export | 20 | Both "Champlain Plastics" and "Essex Chemical" in XML |
| Champlain fire district correct | 20 | fireDistrict contains "Burlington Central" or "Fire Station 3" |
| Kowalski added as Fac. Emergency Coordinator | 20 | Contact "Kowalski" with Fac. Emergency Coordinator type |
| Essex fire district correct | 20 | fireDistrict contains "Essex Fire District 1" |
| Obrecht added as Emergency Contact | 20 | Contact "Obrecht" with Emergency Contact type |

**Pass threshold**: ≥ 70 points
**Wrong-target gate**: Score = 0 if neither target facility is in the export

## Why This Is Very Hard

- Agent must find and import TWO separate data files (no explicit file paths given for import)
- Contact information is not in the task description — agent must read each facility's notes field in CAMEO
- Fire district field is separate from chemical/contact management — agent must navigate to facility settings
- Five independent subtasks spanning different CAMEO UI sections
- Agent must correlate information across facility records and contact assignments
