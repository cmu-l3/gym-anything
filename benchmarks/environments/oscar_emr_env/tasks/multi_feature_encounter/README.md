# Task: Multi-Feature Encounter (Annual Review)

## Overview

**Patient**: Robert MacPherson (DOB: September 17, 1948)
**Difficulty**: Hard
**Environment**: OSCAR EMR

## Clinical Context

Robert MacPherson is a 76-year-old male with hypertension being seen for his annual review. During today's visit, the physician needs to record vital signs, start a new medication for better blood pressure control, and close out an overdue reminder that has been sitting in his chart.

## Goal

Complete three distinct clinical tasks in Robert MacPherson's OSCAR chart:

1. **Record vital signs**: Blood pressure 158/92 mmHg (in the measurements/vitals section of his chart)

2. **Prescribe medication**: Ramipril 10mg by mouth once daily (for hypertension management)

3. **Resolve the open tickler**: Robert has an open reminder in his chart about ordering annual labs. Since the labs have now been done, find this tickler and mark it as complete/resolved.

## Why This Is Hard

- Requires navigating **three separate OSCAR workflows**: measurements/vitals, the prescription/Rx module, AND the tickler module.
- The tickler is a real pre-existing entry that the agent must *discover* — the task description tells the agent it exists and needs resolving, but the agent must find it in the chart.
- Tickler management is a distinct OSCAR feature (separate from clinical notes and prescriptions). Many clinicians overlook this module.
- Correctly recording the BP value AND prescribing the medication AND resolving the tickler are all independent — failing any one reduces the score.
- No step-by-step UI instructions are provided.

## Verification Strategy

### Criterion 1 — Blood pressure recorded (30 pts + 10 bonus)
Check `measurements` table for new BP row. Full 30 pts if BP detected; +10 bonus if value is close to 158/92.

### Criterion 2 — Ramipril active (30 pts)
Check `drugs` table: `SELECT * FROM drugs WHERE demographic_no=X AND GN LIKE '%Ramipril%' AND archived=0`.

### Criterion 3 — Tickler resolved (30 pts)
Check `tickler` table: the pre-seeded tickler (identified by tickler_no saved during setup) should have status='C' (or be deleted).

### Criterion 4 — Ramipril 10mg dose (10 pts)
Dosage field contains '10'.

### Pass Threshold
70 points. Note: Getting all 3 main criteria (BP + Ramipril + Tickler) gives 90 pts. Missing the tickler alone (a distinctive OSCAR feature requiring discovery) drops the score to 60, which is just below the pass threshold — intentional design to require the tickler step.

## Starting State (seeded by setup_task.sh)

- **Measurements**: none (clean slate)
- **Medications**: none (clean slate)
- **Tickler**: one OPEN tickler with message "Annual labs due: fasting glucose and lipid panel — order if not done" — status='A' (active, overdue)

## Database Schema Reference

```sql
-- Measurements
measurements (
  id INT PRIMARY KEY,
  type VARCHAR(50),      -- e.g. 'BP', 'WT'
  demographicNo INT,
  dataField VARCHAR(255) -- the measured value
)

-- Medications
drugs (
  id INT PRIMARY KEY,
  demographic_no INT,
  GN VARCHAR(60),        -- generic name
  dosage VARCHAR(20),
  archived TINYINT       -- 0=active, 1=discontinued
)

-- Ticklers
tickler (
  tickler_no INT PRIMARY KEY,
  demographic_no INT,
  message TEXT,
  status CHAR(1)         -- 'A'=Active, 'C'=Completed
)
```
