# preventive_care_protocol

## Task Overview

**Role**: Nurse Practitioner / Medical Assistant
**Difficulty**: Hard
**Timeout**: 600 seconds
**Max Steps**: 80

A Nurse Practitioner must complete a full annual preventive health visit encounter for an established patient in FreeMED. This task requires navigating to five distinct sections of the EMR — vitals, immunizations, clinical notes, and scheduling — and entering structured clinical data for each.

## Clinical Scenario

**Sherill Botsford** (DOB: 1995-01-24, female, ID 10) presents for her annual preventive exam. She is a healthy 30-year-old due for routine vaccines. The NP must record vitals, administer and document two immunizations, write a preventive visit note, and schedule next year's annual physical.

## Required Actions (5 independent subtasks)

1. **Vital Signs** (date: 2025-03-01)
   - BP: 118/76 mmHg
   - HR: 68 bpm
   - Temperature: 98.2°F
   - Weight: 145 lbs
   - Height: 65 inches

2. **Immunization — Tdap**
   - Vaccine: Tdap (Tetanus, Diphtheria, Pertussis)
   - Date: 2025-03-01
   - Lot number: TDP2024-441
   - Manufacturer: Sanofi Pasteur

3. **Immunization — Influenza**
   - Vaccine: Influenza Quadrivalent (or Influenza/Flu)
   - Date: 2025-10-15
   - Lot number: FLQ2025-112
   - Manufacturer: Seqirus

4. **Clinical Progress Note**
   - Must mention vaccines administered (Tdap and/or Influenza)
   - Must mention preventive exam components (breast exam or cardiovascular assessment)

5. **Follow-up Appointment**
   - Date: 2026-03-01
   - Time: 10:00 AM
   - Purpose: Annual physical / preventive care

## Success Criteria

| Criterion | Points | Check |
|-----------|--------|-------|
| Vital signs recorded with correct values (±tolerance) | 20 | `vitals` table |
| Tdap immunization with correct vaccine/lot/manufacturer | 20 | `immunization` table |
| Influenza immunization with correct vaccine/lot/manufacturer | 20 | `immunization` table |
| Clinical note referencing vaccines and preventive exam | 20 | `pnotes` table |
| Follow-up appointment scheduled for 2026-03-01 | 20 | `scheduler` table |
| **Total** | **100** | |

**Pass threshold**: ≥ 70 points

## Database Schema Reference

```sql
-- Vitals
SELECT bp_systolic, bp_diastolic, heart_rate, temperature, weight, height
FROM vitals WHERE patient = 10 ORDER BY id DESC LIMIT 1;

-- Immunizations
SELECT vaccine, dateof, lot_number, manufacturer
FROM immunization WHERE patient = 10 ORDER BY id DESC LIMIT 5;

-- Clinical notes
SELECT pnotetext FROM pnotes WHERE pnotespat = 10 ORDER BY id DESC LIMIT 1;

-- Scheduler
SELECT caldateof, caltimeof, caldescription
FROM scheduler WHERE calpatient = 10 ORDER BY id DESC LIMIT 5;
```

## Why This Is Hard

The agent must navigate to **five different sections** of FreeMED: vitals entry, two separate immunization records, clinical notes, and the appointment scheduler. Each section has a different UI pattern. The agent must track which vaccines are which, enter lot numbers and manufacturers for each, and write a meaningful clinical note summarizing the visit.
