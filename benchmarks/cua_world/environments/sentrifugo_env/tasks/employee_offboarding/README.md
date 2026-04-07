# employee_offboarding

**Difficulty**: very_hard
**Environment**: Sentrifugo v3.2 HRMS (Ubuntu GNOME, Docker MySQL 5.7)
**Domain**: HR offboarding / onboarding / regional administration

## Overview

HR has issued an offboarding and onboarding manifest for Q1 2026. The agent receives the manifest on the Desktop (`~/Desktop/hr_offboarding_manifest.txt`). It must complete three distinct actions:

1. **Deactivate** 3 departing employees (EMP013, EMP018, EMP020) — do not delete, only deactivate
2. **Add** 2 replacement hires (Carlos Reyes in Sales, Mia Chen in Marketing) with the correct departments and job titles
3. **Create** a new "Austin Office Holidays" regional holiday group with two specific holidays

This is the most complex task in the set, requiring navigation across three separate HRMS modules (Employee management, Holiday management) and careful attention to not confuse deactivation with deletion.

## Setup

The setup script re-activates the 3 departing employees (in case a prior run deactivated them), removes any prior-run EMP021/EMP022 records, removes any prior-run Austin Office Holidays group, drops the manifest on the Desktop, and navigates to the employee list.

## Scoring (100 pts total, pass = 60)

| Criterion | Points |
|-----------|--------|
| EMP013 Daniel Wilson deactivated | 10 |
| EMP018 Nicole Anderson deactivated | 10 |
| EMP020 Lauren Jackson deactivated | 10 |
| Carlos Reyes (EMP021) exists and in Sales dept | 15 |
| Mia Chen (EMP022) exists and in Marketing dept | 15 |
| "Austin Office Holidays" group created | 10 |
| "Texas Independence Day" holiday in group | 15 |
| "Juneteenth" holiday in group | 15 |

New hires in the wrong department receive 7 pts partial credit (pts//2), which caps total partial at 44 pts (below 60 threshold).

## Verification Strategy

The verifier queries `main_users` for deactivation status, `main_users JOIN main_departments` for new hire department assignment, `main_holidaygroups` for the holiday group, and `main_holidaydates` for individual holidays. Uses `exec_in_env` for live MySQL queries.

## Anti-Patterns Addressed

- **AP-4**: Max partial score = 30 (deactivations) + 14 (wrong-dept hires) = 44 < 60 threshold.
- **AP-9**: Holiday absence is not rewarded — the group and each holiday must exist and be active.
