# Task: chronic_panel_audit

## Overview

**ID**: `chronic_panel_audit@1`
**Difficulty**: Very Hard
**Timeout**: 1200 seconds | **Max steps**: 150
**Pass threshold**: 50/100

A GP conducts a quarterly clinical audit of their patient panel. Four patients have planted clinical management gaps — but the agent is not told which patients are affected or how many issues exist. The agent must proactively browse patient records, identify the clinical problems, and take corrective action.

---

## Professional Context

Quarterly clinical panel audits are a standard quality improvement activity for GPs in France (required under ROSP — Rémunération sur Objectifs de Santé Publique). The GP reviews each patient's terrain (allergies/antecedents), prescriptions, and appointment history to identify and correct gaps. This is distinct from a patient-initiated consultation: the GP must be proactive, scanning for problems rather than responding to symptoms.

The four issue types planted represent real and common clinical audit findings:
1. **Chronic disease without treatment**: A patient diagnosed with hypertension + type 2 diabetes has never received a prescription
2. **Undertreated comorbidity**: A patient with atrial fibrillation is on aspirin only — current guidelines require anticoagulation for CHA2DS2-VASc ≥ 2
3. **Overdue follow-up**: A COPD patient has not been seen in >9 months — annual spirometry and clinical review is required
4. **Contraindicated medication**: A patient with migraine with aura is on a combined oral contraceptive — this is an absolute contraindication due to stroke risk

---

## Planted Issues (Hidden from Agent)

| Patient | DOB | Issue | Expected Correction |
|---------|-----|-------|---------------------|
| DUBOIS Marie-Claire | 1960-07-21 | HTA + T2DM documented, no prescription | Create prescription with antihypertensive and/or antidiabetic |
| LAMBERT Anne | 1947-10-07 | Atrial fibrillation, aspirin-only (no anticoagulant) | New prescription with anticoagulant (apixaban, rivaroxaban, etc.) |
| PERRIN Martine | 1950-02-02 | COPD, last visit 2025-05-15 (>9 months) | Schedule follow-up appointment in agenda |
| NICOLAS Sandrine | 1981-09-06 | Migraine with aura + combined OCP (ethinylestradiol) | New prescription without combined OCP |

---

## Scoring (100 pts)

| Patient | Criterion | Points |
|---------|-----------|--------|
| DUBOIS Marie-Claire | New prescription created | 15 |
| DUBOIS Marie-Claire | Prescription contains antihypertensive or antidiabetic | 10 |
| LAMBERT Anne | New prescription created | 10 |
| LAMBERT Anne | Prescription includes anticoagulant | 15 |
| PERRIN Martine | Follow-up appointment scheduled in agenda | 20 |
| PERRIN Martine | Appointment date is in the future | 5 |
| NICOLAS Sandrine | New prescription created | 10 |
| NICOLAS Sandrine | New prescription does NOT contain combined OCP | 15 |
| **Total** | | **100** |

**Pass threshold**: 50/100 (need to correctly handle 2 of 4 issues)

---

## Verification Strategy

1. **Baseline recording**: setup_task.sh records max PrimKey for RubriquesHead and agenda before task
2. **New-only filter**: Only rubrics with PrimKey > baseline are considered as new agent work
3. **Per-patient checks**:
   - DUBOIS: New TypeRub=20020100 rubric with antihypertensive/antidiabetic keywords
   - LAMBERT: New TypeRub=20020100 rubric with anticoagulant drug name
   - PERRIN: New agenda entry with PrimKey > baseline, date in future
   - NICOLAS: New TypeRub=20020100 rubric without ethinylestradiol/combined OCP keywords
4. **No wrong-patient penalty**: Agent discovers issues independently, extra consultations or notes on other patients do not reduce score

---

## Why This Is Very Hard

- **Discovery required**: The agent is not told which 4 of 20 patients have issues — it must browse all records
- **Multiple issue types**: Issues span prescriptions, agenda entries, and drug-disease interactions
- **Clinical reasoning**: The agent must understand HAS medication guidelines, AF anticoagulation thresholds, OCP contraindications
- **High action count**: Fixing 4 patients requires navigating 4 separate patient files and performing distinct corrective actions

---

## File Structure

```
tasks/chronic_panel_audit/
├── README.md           # This file
├── task.json           # Task specification
├── setup_task.sh       # Plants clinical issues, records baseline
├── export_result.sh    # Queries corrective actions taken
└── verifier.py         # Programmatic scoring
```
