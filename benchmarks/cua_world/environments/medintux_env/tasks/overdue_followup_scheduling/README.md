# Task: Overdue Follow-up Scheduling

## Overview

**Difficulty**: Very Hard
**Environment**: MedinTux (French general practice EMR, Wine/MySQL)
**Occupation context**: General Practitioner / Medical Secretary

This task simulates a chronic disease management audit — a routine but critical task in French general practice. The GP (or their secretary) must review all patient consultation histories, identify which chronic patients have not had a follow-up in over 6 months, and schedule appointments for those who are overdue.

## Professional Context

French GP practices participating in the CAPI (Contrat d'Amélioration des Pratiques Individuelles) program are required to maintain regular follow-up intervals for chronic patients. Specifically:
- Diabetic patients: follow-up every 3–6 months
- Hypertensive patients: follow-up every 6 months
- Hypothyroid patients: TSH check every 6 months
- Asthma patients: follow-up every 6 months

Missing these follow-ups results in both clinical risk and administrative penalties in the CAPI evaluation.

## Task Goal (VERY HARD — agent must discover targets independently)

The agent must:
1. Browse through all patients in the MedinTux database
2. Review each patient's consultation history to find the date of their most recent consultation
3. Identify patients whose last consultation was before September 2025 (>6 months before March 2026)
4. Schedule a new follow-up appointment in the MedinTux agenda for each overdue patient
5. NOT schedule appointments for patients who already have a recent consultation

**The agent is not told which patients are overdue.** It must discover this by reviewing records.

## Patients in Database (agent must identify)

| Patient | Last consult | Status |
|---------|-------------|--------|
| PETIT Nathalie | 2025-06-15 | **OVERDUE** |
| DURAND Christophe | 2025-07-10 | **OVERDUE** |
| GIRARD Michel | 2025-05-22 | **OVERDUE** |
| MOREL Sylvie | 2025-08-01 | **OVERDUE** |
| HENRY Emmanuel | 2025-08-20 | **OVERDUE** |
| ROUX Celine | 2025-11-20 | Not overdue |
| BLANC David | 2025-12-10 | Not overdue |

## Verification Strategy

The verifier checks the `agenda` table for new entries linked to overdue patient GUIDs or names.

| Criterion | Points |
|-----------|--------|
| PETIT Nathalie scheduled | 20 |
| DURAND Christophe scheduled | 20 |
| GIRARD Michel scheduled | 20 |
| MOREL Sylvie scheduled | 20 |
| HENRY Emmanuel scheduled | 20 |
| ROUX Celine incorrectly scheduled | -10 |
| BLANC David incorrectly scheduled | -10 |

**Pass threshold**: 60 points (need to correctly schedule at least 3 overdue patients)
