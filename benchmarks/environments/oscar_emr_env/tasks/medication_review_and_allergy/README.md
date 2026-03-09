# Task: Medication Review and Allergy Update

## Overview

**Patient**: Fatima Al-Hassan (DOB: August 9, 1978)
**Difficulty**: Hard
**Environment**: OSCAR EMR

## Clinical Context

Fatima Al-Hassan is a 47-year-old female being reviewed for diabetes management. A data entry error was made previously — Amiodarone (an antiarrhythmic she has never taken) was entered in her medication list. This error must be corrected. Additionally, her allergy profile is incomplete and she needs a new medication started for diabetes.

## Goal

Complete three distinct actions in Fatima Al-Hassan's OSCAR chart:

1. **Discontinue/archive the Amiodarone prescription** — this was entered by mistake. Find it in her medications list and mark it as discontinued/inactive.

2. **Add an allergy**: ASA (Acetylsalicylic Acid) — Reaction: Gastrointestinal upset, Severity: Moderate.

3. **Prescribe a new medication**: Metformin 500mg by mouth twice daily (for Type 2 diabetes management).

## Why This Is Hard

- Requires **three distinct actions** across different OSCAR chart sections: (1) editing an existing medication entry to archive it, (2) adding to the allergy section, and (3) prescribing a new medication.
- The agent must identify which medication to archive and which to add — not just blindly add entries.
- Archiving/discontinuing an existing medication in OSCAR is a different workflow than adding a new one.
- The agent must understand that the Amiodarone is the "incorrect" one (described in the task) and act accordingly.
- No step-by-step UI navigation is provided.

## Verification Strategy

### Criterion 1 — Amiodarone archived/discontinued (30 pts)
Check `drugs` table: `SELECT archived FROM drugs WHERE demographic_no=X AND GN LIKE '%Amiodarone%'` — expected value: 1 (archived) or row deleted.

### Criterion 2 — ASA allergy added and active (30 pts)
Check `allergies` table: `SELECT * FROM allergies WHERE demographic_no=X AND DESCRIPTION LIKE '%ASA%' AND archived=0`.

### Criterion 3 — Metformin active prescription (30 pts)
Check `drugs` table: `SELECT * FROM drugs WHERE demographic_no=X AND GN LIKE '%Metformin%' AND archived=0`.

### Criterion 4 — Correct dose 500mg (10 pts)
Check `dosage` field in Metformin row contains '500'.

### Pass Threshold
70 points.

## Starting State

The setup script seeds:
- **Amiodarone 200mg OD** — active (archived=0) — this is the erroneous entry to fix
- No allergies (clean slate)

## Database Schema Reference

```sql
-- Medications (drugs)
drugs (
  id INT PRIMARY KEY,
  demographic_no INT,
  GN VARCHAR(60),     -- generic name (e.g., 'Amiodarone', 'Metformin')
  BN VARCHAR(60),     -- brand name
  dosage VARCHAR(20),
  archived TINYINT,   -- 0=active, 1=discontinued/archived
  rx_date DATE
)

-- Allergies
allergies (
  ALLERGY_ID INT PRIMARY KEY,
  demographic_no INT,
  DESCRIPTION VARCHAR(255),         -- allergen
  reaction VARCHAR(255),
  severity_of_reaction CHAR(2),    -- 'M'=Mild, 'Mo'=Moderate, 'S'=Severe
  archived TINYINT DEFAULT 0
)
```
