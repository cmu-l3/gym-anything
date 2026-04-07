# Medication Interaction Audit — CKD Stage 3b

**Environment**: openemr_env
**Difficulty**: very_hard
**Occupation**: Clinical Pharmacist / Hospitalist Physician
**Industry**: Healthcare / Hospital System

## Scenario

Patient James Kowalski (DOB: 1968-04-15) has been newly diagnosed with chronic kidney disease stage 3b (eGFR 38 mL/min/1.73m²). His primary care physician has requested an urgent medication reconciliation to identify and address any drugs that are contraindicated or require modification at this level of kidney function.

The patient's current medication list was entered before the CKD diagnosis and has not been reviewed for renal dose adjustments. At CKD stage 3b (eGFR 30–44 mL/min/1.73m²), several classes of medications pose significant risks:

- **Metformin**: Risk of lactic acidosis; should be discontinued when eGFR < 45 mL/min
- **NSAIDs** (e.g., ibuprofen, naproxen): Nephrotoxic, worsen renal perfusion, contraindicated in CKD
- **Nitrofurantoin**: Ineffective at eGFR < 45 and potentially toxic due to metabolite accumulation
- **ACE inhibitors/ARBs** (e.g., lisinopril): May be continued with close monitoring; often renoprotective

## Task Difficulty Justification (very_hard)

The task description provides the clinical context (new CKD3b diagnosis, eGFR 38) but does NOT specify:
- Which medications the patient is currently taking
- Which specific medications need to be changed
- What laboratory monitoring to order
- What the clinical note should contain

The agent must independently apply pharmacological knowledge to identify contraindicated drugs, perform the appropriate clinical actions, and preserve medications that are appropriate or beneficial in CKD.

## Scoring

| Criterion | Points | Notes |
|-----------|--------|-------|
| Metformin discontinued | 20 | Critical — lactic acidosis risk in CKD3b |
| NSAIDs (Ibuprofen) discontinued | 20 | Critical — nephrotoxic |
| Nitrofurantoin discontinued | 20 | Critical — ineffective + toxic in CKD3b |
| All 3 safe medications still active | 20 | Anti-gaming gate (Amlodipine, Atorvastatin, Lisinopril) |
| Monitoring labs ordered (≥1: BMP/CMP/Creatinine/Urinalysis) | 10 | Clinical monitoring |
| Clinical note documenting medication review | 10 | Documentation standard |
| **Total** | **100** | |
| **Pass threshold** | **70** | |

### Strategy Enumeration (Anti-Gaming Validation)

| Strategy | Score | Passes? |
|----------|-------|---------|
| Do nothing | 20 | No |
| Discontinue all 6 medications | 60 | No (anti-gaming fails; 60 < 70) |
| Correct: discontinue 3 bad + keep 3 good + labs + note | 100 | Yes |
| Discontinue 2 of 3 bad only + keep all safe + labs | 70 | Borderline yes |
| Discontinue any 1 safe medication | ≤40 | No |

## Feature Matrix

| Feature | Used |
|---------|------|
| Patient chart navigation | ✓ |
| Medication management (discontinue) | ✓ |
| Laboratory order entry | ✓ |
| Clinical documentation (notes) | ✓ |
| CKD pharmacology domain knowledge | ✓ |
