# vaccine_audit_and_schedule

## Overview

**Difficulty**: very_hard
**Environment**: NOSH ChartingSystem (nosh_env@0.1)
**Occupation context**: Medical Secretary / Administrative Assistant coordinating preventive care outreach
**Features tested**: Immunizations, Schedule (appointments), Patient chart navigation

## Domain Context

Preventive care audits are a standard part of running a primary care practice. Staff periodically review which patients are missing age-appropriate vaccinations and schedule appointments for vaccine administration. For patients 65+, the CDC recommends Zoster (Shingrix) vaccine. This task simulates a real preventive care workflow for elderly patients.

## Goal

The agent must (without being told which vaccines or which patients):

1. **Identify** which senior patients (65+) have gaps in their vaccination record
2. **Record** the missing vaccine(s) in each patient's immunization history (today's date)
3. **Schedule** a follow-up appointment on 2026-09-15 at 9:00 AM for each patient with gaps

One patient is already fully vaccinated and must NOT receive duplicate entries.

## Starting State (seeded by setup_task.sh)

| PID | Name | DOB | Age | Has Flu | Has Pneumovax | Has Shingrix |
|-----|------|-----|-----|---------|---------------|--------------|
| 27 | Virginia Slagle | 1948-06-10 | 77 | ✓ | ✓ | ✗ |
| 28 | Harold Dunbar | 1945-11-23 | 80 | ✓ | ✗ | ✗ |
| 29 | Agnes Morley | 1951-08-04 | 74 | ✓ | ✓ | ✗ |
| 30 | Clarence Webb | 1950-03-17 | 75 | ✓ | ✓ | ✓ (noise) |

The agent must recognize that Shingrix (Zoster vaccine) is the missing element for pids 27, 28, 29.

## Success Criteria

The task is complete when:
1. Pids 27, 28, 29 each have a Shingrix/Zoster vaccine entry in their immunization record
2. Pids 27, 28, 29 each have an appointment scheduled on 2026-09-15

## Verification Strategy

**Export script** (`export_result.sh`) queries:
- Immunization counts before and after (baseline vs. current)
- Whether a Shingrix/Zoster record exists (checks imm_immunization for 'shingrix'/'zoster' or CVX code 187/188)
- Whether a 2026-09-15 appointment exists in the schedule table

**Verifier** (`verifier.py::verify_vaccine_audit_and_schedule`) scores:
| Criterion | Points |
|-----------|--------|
| Shingrix recorded for Virginia Slagle (pid 27) | 15 |
| 2026-09-15 appointment for pid 27 | 10 |
| Shingrix recorded for Harold Dunbar (pid 28) | 15 |
| 2026-09-15 appointment for pid 28 | 10 |
| Shingrix recorded for Agnes Morley (pid 29) | 15 |
| 2026-09-15 appointment for pid 29 | 10 |
| All 3 patients fully vaccinated + scheduled (bonus) | 25 |
| **Total (without bonus)** | **75** |
| **Total (with full bonus)** | **100** |
| **Pass threshold** | **60** |

## Partial Credit Structure

Max partial without bonus = 75 pts (all vaccines + all appointments, no bonus). ✓
Min to pass = 60 pts (2 complete patients = 2×25 = 50 pts — must get bonus or 3rd patient partial).
Actually: 2 complete patients (15+10+15+10=50) + 3rd patient vaccine only (15) = 65 pts ≥ 60. ✓

## Relevant Database Tables

```sql
-- Check immunization history
SELECT pid, imm_immunization, imm_date, imm_cvx FROM immunizations WHERE pid IN (27,28,29,30);

-- Check scheduled appointments
SELECT pid, start, title, visit_type FROM schedule WHERE pid IN (27,28,29,30);
```

## Edge Cases

- **Agent uses different vaccine name spelling**: Verifier accepts 'shingrix', 'zoster' (case-insensitive), or CVX codes 187/188
- **Agent schedules appointment at different time**: Verifier only checks for 2026-09-15 date, not the exact time
- **Agent adds Shingrix for noise patient (30)**: Not penalized (noise patient is checked but score not deducted)
- **Agent adds wrong vaccine**: Any new vaccine entry counts as "new_vaccine_added" (partial credit), but only Shingrix-specific detection gives full credit

## Anti-Gaming Notes

- Baseline immunization counts recorded after cleanup
- Both specific Shingrix detection AND general new-vaccine detection used for scoring robustness
- Noise patient (pid 30) already has Shingrix — adding a duplicate would show in curr_imm_count but the noise pid is tracked separately and not included in scoring
