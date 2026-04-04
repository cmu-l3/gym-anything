# Task: Record Vitals and Encounter Note

## Overview

**Patient**: Maria Santos (DOB: April 27, 1994)
**Difficulty**: Hard
**Environment**: OSCAR EMR

## Clinical Context

Maria Santos is a 30-year-old female presenting for her annual physical examination. She has no acute complaints. The physician needs to document today's visit, which requires recording vital signs in the measurements section AND writing a clinical encounter note — two distinct workflows in OSCAR.

## Goal

Complete the annual physical documentation for Maria Santos:

1. **Vital signs** (in the measurements/vitals section of her chart):
   - Blood Pressure: **118/76 mmHg**
   - Weight: **63 kg**
   - Height: **167 cm**

2. **Encounter note**: Create a clinical note documenting this as an annual physical exam, noting the patient is healthy, BMI approximately 22.6, and no acute concerns identified.

## Why This Is Hard

- Requires navigating **two separate documentation workflows** in OSCAR: the measurements/vitals form and the encounter note editor — these are separate sections of the chart accessed differently.
- The agent must know that vitals go in the *measurements* section (not just into the note text) and that a separate encounter note must also be created.
- Step-by-step UI navigation is not provided — the agent must explore the chart to find both sections.

## Verification Strategy

### Criterion 1 — Any vital measurement recorded (20 pts)
Check `measurements` table: `SELECT COUNT(*) FROM measurements WHERE demographicNo = <patient_no>` returns > 0 after task start.

### Criterion 2 — Blood pressure recorded (25 pts)
Check `measurements` table for a row where `type` contains 'BP' or 'blood' (case-insensitive), or `dataField` contains the value '118' and '76'. Partial credit if 3+ total measurements recorded.

### Criterion 3 — Weight and height recorded (25 pts)
Check `measurements` table for rows where `type` contains 'wt'/'weight' and 'ht'/'height'. 12 pts partial if only one.

### Criterion 4 — Encounter note created (30 pts)
Check `casemgmt_note` table: new row for this patient with `len(note) > 50`. Full 30 pts if note content includes annual/physical keywords; 20 pts if content exists without keywords.

### Pass Threshold
70 points.

## Database Schema Reference

```sql
-- Measurements (vitals)
measurements (
  id INT PRIMARY KEY,
  type VARCHAR(50),        -- e.g., 'BP', 'WT', 'HT', 'BMI'
  demographicNo INT,
  dataField VARCHAR(255),  -- the measured value
  dateObserved DATETIME,
  dateEntered DATETIME
)

-- Encounter notes
casemgmt_note (
  note_id INT PRIMARY KEY,
  demographic_no INT,
  note MEDIUMTEXT,
  observation_date DATETIME,
  archived TINYINT DEFAULT 0
)
```

## Setup Notes

- Maria Santos is pre-seeded in the database (Patient ID in seed_patients.sql: Patient 12)
- Setup script clears any pre-existing measurements and notes for a clean baseline
- No medications, allergies, or diagnoses exist for Maria Santos
