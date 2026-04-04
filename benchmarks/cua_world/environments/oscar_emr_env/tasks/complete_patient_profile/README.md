# Task: Complete Patient Profile (Transfer of Care)

## Overview

**Patient**: Jean-Pierre Bouchard (DOB: June 30, 1965, Ottawa)
**Difficulty**: Hard
**Environment**: OSCAR EMR

## Clinical Context

Jean-Pierre Bouchard is a 60-year-old male who has transferred from another clinic. His OSCAR chart currently has no medications and no allergies on file. The previous clinic has faxed over his current medication list and allergy profile, and the family physician must enter this information into OSCAR to complete his cumulative patient profile (CPP).

## Goal

Set up Jean-Pierre Bouchard's cumulative patient profile with the following information from his previous clinic:

**Allergies to add:**
1. **Penicillin** — Reaction: Anaphylaxis, Severity: Severe
2. **Sulfonamides / Sulfa drugs** — Reaction: Skin rash, Severity: Moderate

**Medications to add (current active medications):**
1. **Metformin** 500mg by mouth twice daily (for Type 2 diabetes)
2. **Ramipril** 10mg by mouth once daily (for hypertension)

## Why This Is Hard

- Requires navigating **three distinct areas** of the OSCAR chart: the allergy section (CPP), and the prescription/Rx section — plus logging in first.
- The agent must add two entries to the allergy section AND two to the medications section, keeping track of what's been done.
- Step-by-step navigation is not provided. The agent must discover how OSCAR organizes the CPP, where to find the allergy form, and where the Rx module is.
- The agent must correctly fill in reaction type AND severity for each allergy.

## Verification Strategy

### Criterion 1 — Penicillin allergy (25 pts, up to 30 with correct severity)
Check `allergies` table: `SELECT * FROM allergies WHERE demographic_no=X AND DESCRIPTION LIKE '%penicillin%' AND archived=0`.
Bonus 5 pts if severity_of_reaction is 'S' (Severe).

### Criterion 2 — Sulfonamide allergy (20 pts)
Check `allergies` table: `SELECT * FROM allergies WHERE demographic_no=X AND DESCRIPTION LIKE '%sulfa%' AND archived=0`.

### Criterion 3 — Metformin prescription (25 pts)
Check `drugs` table: `SELECT * FROM drugs WHERE demographic_no=X AND GN LIKE '%metformin%' AND archived=0`.

### Criterion 4 — Ramipril prescription (25 pts)
Check `drugs` table: `SELECT * FROM drugs WHERE demographic_no=X AND GN LIKE '%ramipril%' AND archived=0`.

### Pass Threshold
70 points.

## Database Schema Reference

```sql
-- Allergies
allergies (
  ALLERGY_ID INT PRIMARY KEY,
  demographic_no INT,
  DESCRIPTION VARCHAR(255),    -- allergen name
  reaction VARCHAR(255),
  severity_of_reaction CHAR(2), -- 'M'=Mild, 'Mo'=Moderate, 'S'=Severe
  TYPECODE INT,                -- 0=Drug, 1=Food, 2=Other
  archived TINYINT DEFAULT 0
)

-- Medications
drugs (
  id INT PRIMARY KEY,
  demographic_no INT,
  GN VARCHAR(60),    -- generic name
  BN VARCHAR(60),    -- brand name
  dosage VARCHAR(20),
  route VARCHAR(20),
  freqcode VARCHAR(6),  -- e.g. 'od'=once daily, 'bid'=twice daily
  archived TINYINT DEFAULT 0
)
```

## Setup Notes

- Jean-Pierre Bouchard is pre-seeded in the database (Patient 9 in seed_patients.sql)
- Setup script clears any pre-existing allergies and medications for a clean baseline
- Jean-Pierre has no medications or allergies in the seed data
