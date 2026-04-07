# Task: Contact Network Rebuild

## Overview

An emergency contact management task requiring the agent to add required Facility Emergency Coordinator contacts to two chemical facilities whose Tier II records are missing them. Under EPCRA Section 312, every facility must designate emergency contacts in its Tier II submission.

**Difficulty**: Hard
**Domain**: EPCRA compliance / emergency response planning
**Real workflow**: LEPC coordinators and corporate EHS managers regularly update CAMEO when personnel changes occur or when a compliance review reveals missing contact entries.

## Goal

Two specific contacts must be added to their respective facilities and the dataset exported as XML.

End state: `C:\Users\Docker\Documents\CAMEO\contacts_updated.xml` contains both facilities with the required emergency contacts linked to each facility.

## Task Description

Import `C:\workspace\data\central_vt_facilities.xml`. Both facilities are missing a required Facility Emergency Coordinator.

Add:
1. **Montpelier Industrial Supply**: Robert Flanagan, Emergency Response Coordinator, phone 802-555-0219, type: Fac. Emergency Coordinator
2. **Richmond Processing Plant**: Maria Santos, Plant Safety Officer, phone 802-555-0347, types: Fac. Emergency Coordinator AND Emergency Contact

Export the updated dataset to `C:\Users\Docker\Documents\CAMEO\contacts_updated.xml`.

## Verification Strategy

The verifier parses the exported XML for contact records with specific last names, contact types, and phone numbers.

### Scoring (100 points)

| Criterion | Points | Check |
|-----------|--------|-------|
| Flanagan added with Fac. Emergency Coordinator type | 25 | Contact with last name "Flanagan" has type containing "Fac. Emergency Coordinator" |
| Flanagan phone 802-555-0219 | 25 | Flanagan contact record contains phone 802-555-0219 |
| Santos added with Fac. Emergency Coordinator type | 25 | Contact with last name "Santos" has type containing "Fac. Emergency Coordinator" |
| Santos Emergency Contact type + phone 802-555-0347 | 25 | Santos has "Emergency Contact" type AND phone 802-555-0347 |

**Pass threshold**: ≥ 70 points
**Wrong-target gate**: Score = 0 if export doesn't contain Montpelier Industrial Supply or Richmond Processing Plant

## Notes

- Contacts must be linked to their respective facilities (not just added to the global contacts list)
- The certifier field in each facility's XML hints at who the contact should be
- The facility notes also contain contact information for the agent to discover
