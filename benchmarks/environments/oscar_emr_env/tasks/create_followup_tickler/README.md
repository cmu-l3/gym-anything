# Task: Create Encounter Note and Followup Tickler

## Overview

**Patient**: Thomas Bergmann (DOB: January 19, 1960, Kitchener)
**Difficulty**: Hard
**Environment**: OSCAR EMR

## Clinical Context

Thomas Bergmann is a 65-year-old male who presented urgently for exertional chest pain. ECG showed ST changes consistent with ischemia. The family physician has assessed him and needs to (1) document today's visit in an encounter note, and (2) create a tickler (reminder) to follow up on the cardiology referral that was made.

## Goal

Complete clinical documentation for Thomas Bergmann:

1. **Encounter note**: Write a visit note that includes:
   - That the patient presented with exertional chest pain
   - That ECG showed ST changes
   - That he is being referred to cardiology

2. **Tickler (reminder)**: Create a reminder in his chart with text about following up on the cardiology referral if no appointment is received within 2 weeks.

## Why This Is Hard

- Requires navigating **two distinct OSCAR workflows**: the encounter note editor (eChart) AND the tickler/reminder module — which are separate features of OSCAR.
- Most new users of OSCAR only know about one or the other — using both in the same session requires discovering the tickler feature.
- The tickler module is separate from the encounter documentation workflow and requires the agent to find it in the chart.
- No step-by-step UI navigation is provided.

## Verification Strategy

### Criterion 1 — Encounter note created (25 pts)
Check `casemgmt_note`: new row for this patient exists after task start with content length > 50 chars.

### Criterion 2 — Note has clinical content (25 pts)
Check that note text contains relevant clinical keywords: 'chest pain', 'ECG'/'EKG', and/or 'cardiology'/'referr'. Full 25 pts for 2+ keywords; 12 pts for 1 keyword.

### Criterion 3 — Tickler created (25 pts)
Check `tickler` table: new row for this patient exists after setup.

### Criterion 4 — Tickler has relevant content (25 pts)
Check that tickler message contains 'cardiology' or 'referral' or 'follow'. Full 25 pts; 12 pts if tickler exists with any content.

### Pass Threshold
70 points.

## Database Schema Reference

```sql
-- Encounter notes
casemgmt_note (
  note_id INT PRIMARY KEY,
  demographic_no INT,
  note MEDIUMTEXT,
  observation_date DATETIME,
  archived TINYINT DEFAULT 0
)

-- Ticklers (reminders)
tickler (
  tickler_no INT PRIMARY KEY,
  demographic_no INT,
  message TEXT,
  status CHAR(1),       -- 'A'=Active, 'C'=Completed
  service_date DATETIME,
  creator VARCHAR(6),
  task_assigned_to VARCHAR(255),
  priority VARCHAR(6) DEFAULT 'Normal'
)
```

## Setup Notes

- Thomas Bergmann is pre-seeded in the database (Patient 13 in seed_patients.sql)
- Setup script clears any pre-existing encounter notes and ticklers for a clean baseline
- Thomas has no medications, allergies, or diagnoses in the seed data
