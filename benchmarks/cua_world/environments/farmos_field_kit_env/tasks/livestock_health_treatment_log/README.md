# livestock_health_treatment_log

## Overview

**Role**: Farmworker, Farm, Ranch, and Aquacultural Animals
**Difficulty**: Very Hard
**Environment**: farmOS Field Kit (Android app, offline mode)

A cattle farmworker must document a complete bovine respiratory disease (BRD) outbreak response in farmOS Field Kit. These records are required for USDA-APHIS veterinary compliance, beef marketing withdrawal period tracking, and feedlot health management. The worker must create 5 logs across two separate days representing a realistic health event cycle — initial assessment, treatment, sick pen setup, 48-hour follow-up, and veterinary hold.

## Why This Is Hard

- 5 logs across mixed types: Observation ×2, Input ×2, Activity ×1
- Mixed Done/Not Done status: logs 1–3 are Done, logs 4–5 are NOT Done — agent must correctly toggle the done status differently for each entry
- Two logs represent a "follow-up" scenario requiring specific medical terminology in notes
- The Input log type must be correctly selected for antibiotic treatment records
- Times repeat across a 2-day scenario (7:00 AM and 9:00 AM appear twice) — agent must correctly differentiate entries by name
- Long, medically precise notes with drug names, dosages, and withdrawal periods

## Required Logs (in any order)

| # | Log Name | Type | Time | Done | Purpose |
|---|----------|------|------|------|---------|
| 1 | Pen 12 BRD respiratory assessment | Observation | 7:00 AM | Yes | Initial health assessment |
| 2 | Enrofloxacin BRD treatment 12 head | Input | 9:00 AM | Yes | Antibiotic treatment record |
| 3 | Sick pen setup and animal movement | Activity | 9:45 AM | Yes | Animal movement record |
| 4 | 48hr BRD treatment response check | Observation | 7:00 AM | No | Follow-up monitoring |
| 5 | Non-responder vet exam and hold | Input | 9:00 AM | No | Pending vet decision |

## Verification Strategy

The export script navigates to the Tasks list and dumps the UI hierarchy to `/sdcard/ui_dump_livestock.xml`. The verifier checks for each required log name.

**Scoring (100 points total)**:
- Each log name found in Tasks list: 20 points
- Pass threshold: 80 points (4 of 5 logs correct)

## Domain Context

USDA-APHIS regulations (9 CFR Part 86) require detailed records of:
- Individual animal identification at treatment
- Drug name, lot number, and withdrawal period
- Treatment date and dosage
- Treatment outcome and follow-up

The Input log type is used for livestock treatments (medications, vaccines) as well as field inputs (fertilizers, chemicals). The "done: false" status for the follow-up logs reflects that these records remain open pending veterinary assessment — a common workflow in livestock health management.
