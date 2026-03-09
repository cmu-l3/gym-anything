# oc_diabetic_monitoring — Diabetes HbA1c Compliance Audit

## Overview

**Difficulty**: Very Hard
**Occupation**: Clinical Research Coordinator
**Environment**: OpenClinic GA Hospital Information System

A quarterly diabetes protocol compliance task. All four patients have elevated fasting glucose (GLUC > 126 mg/dL), but only three need HbA1c orders. The agent must read each patient's lab history and apply the 90-day protocol rule to determine who needs a new order vs. who is already current.

## Domain Context

Clinical Research Coordinators maintain diabetes management protocol compliance. The protocol states: any patient with GLUC > 126 mg/dL must have HbA1c (glycated hemoglobin) tested within 90 days. This task requires cross-referencing glucose results with HbA1c history dates — not just checking if HbA1c has ever been done.

## Task Setup (Seeded State)

| Patient | ID | GLUC | Last HbA1c | Needs Order |
|---|---|---|---|---|
| Ana Ferreira | 10001 | 156 mg/dL | Never | **YES** |
| Maria Santos | 10005 | 189 mg/dL | 100 days ago | **YES** (stale) |
| Priya Sharma | 10007 | 142 mg/dL | Never | **YES** |
| Elena Popescu | 10010 | 135 mg/dL | 45 days ago | NO (current) |

All 4 patients have elevated GLUC. The agent must look at HbA1c history — not just GLUC — to make the right decisions.

## Expected End State

After task completion:
- Ana Ferreira: 1+ new HbA1c order placed after task start
- Maria Santos: 1+ new HbA1c order placed after task start
- Priya Sharma: 1+ new HbA1c order placed after task start
- Elena Popescu: 0 new HbA1c orders (do NOT over-order)

## Scoring

| Criterion | Points | Condition |
|---|---|---|
| C1: HbA1c ordered for Ana | 25 | new orders after start >= 1 |
| C2: HbA1c ordered for Maria | 25 | new orders after start >= 1 |
| C3: HbA1c ordered for Priya | 25 | new orders after start >= 1 |
| C4: Elena NOT over-ordered | 25 | new orders after start == 0 |

**Pass threshold**: 75/100
**Do-nothing state**: 25/100 (C4 passes because no new order exists for Elena) → `passed=False`

## Verification Strategy

- `setup_task.sh` records task start timestamp to `/tmp/diabetic_task_start_ts`
- `export_result.sh` queries `requestedlabanalyses` for new HbA1c orders placed AFTER start
- Result written to `/tmp/oc_diabetic_monitoring_result.json`
- `verifier.py` copies JSON via `copy_from_env`, checks per-patient new order counts

## Key Database Tables

- `openclinic_dbo.requestedlabanalyses`
  - `patientid`, `analysiscode` ('HBA1C', 'GLUC'), `requestdatetime`, `resultvalue`

## Why This Is Very Hard

- All 4 patients have elevated glucose — the agent cannot use GLUC alone to decide
- Must read and interpret date-stamped lab history to determine staleness
- The 90-day rule requires date arithmetic on lab records
- One patient (Elena) is a "false positive" by GLUC alone — incorrectly ordering for her loses points
