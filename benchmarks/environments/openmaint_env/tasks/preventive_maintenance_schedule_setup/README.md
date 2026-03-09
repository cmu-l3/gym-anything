# Preventive Maintenance Schedule Setup

## Domain Context

Facilities planners at commercial real estate firms must establish preventive
maintenance programs when onboarding new CMMS software. Quarterly HVAC preventive
maintenance is one of the most common PM schedules, requiring per-building activity
cards with detailed task checklists, correct building linkages, and appropriate
priority classifications.

**Occupation:** Maintenance and Repair Workers, General (SOC 49-9071.00)
**Industry:** Commercial Real Estate

## Goal

Create a quarterly HVAC preventive maintenance schedule covering all buildings in
the system. The agent must:
1. Create three new PM activity cards — one per building — each with Code
   following the pattern `PM-HVAC-Q-{BuildingCode}`
2. Link each activity to the correct building record
3. Include all 5 required maintenance tasks in the description/notes:
   filter replacement, coil cleaning, refrigerant level check, thermostat
   calibration, and condensate drain inspection
4. Set priority to medium/normal on all new PMs
5. Preserve all existing maintenance records (do not delete or modify)

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| C1 Created | 25 | 3 new PM activities exist with correct Code pattern (15 pts creation + 10 pts code match) |
| C2 Buildings | 25 | Each PM references a different valid building |
| C3 Tasks | 20 | Each PM includes all 5 required maintenance tasks in description/notes |
| C4 Priority | 15 | All PMs have priority set to medium/normal |
| C5 Preserved | 15 | Existing maintenance records not deleted |

**Pass threshold:** 60/100

## Verification Strategy

- **Setup** discovers the PM class (process or card), records baseline PM count
  and existing PM IDs. Places requirements specification on desktop.
- **Export** retrieves all PM records, identifies new ones (not in baseline),
  extracts building references, priority, notes, and task keywords.
- **Verifier** scores each criterion. Do-nothing detection: if no new PMs created,
  score = 0.

## Schema Reference

- **Class:** PreventiveMaint (process) or PreventiveActivity (card)
- **Key fields:** Code, Description, Building (reference), Frequency, Priority (lookup), Notes
- **Baseline file:** `/tmp/pm_baseline.json`
- **Result file:** `/tmp/pm_result.json`

## Task Input File

`/home/ga/Desktop/pm_requirements.txt` contains the full PM specification
including naming convention, frequency, priority, and the 5 required maintenance
tasks with descriptions.

## Edge Cases

- PM class may be a process class (requiring process instance creation via UI)
  or a card class (standard form).
- Agent must discover the correct buildings from the system rather than hardcoding.
- The "Notes" field may not exist in all class configurations; Description field
  is an acceptable alternative for task items.
- Agent may create more than 3 PMs (e.g., one per building if >3 buildings exist).
  Verifier scores top 3.
