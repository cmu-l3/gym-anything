# anticoagulation_safety_review

## Domain Context

Registered Nurses on cardiac step-down units perform pre-anticoagulation safety checklists before initiating anticoagulants such as warfarin or apixaban. Critical steps include allergy verification, baseline vital signs, and problem list completeness — all of which affect drug selection and dosing.

## Patient

**Rosario Ortiz** (DOB: 1944-06-15) — admitted to the cardiac step-down unit prior to anticoagulation initiation for newly diagnosed paroxysmal atrial fibrillation.

## Goal

Complete three nursing documentation tasks required before anticoagulants can be started:

1. **Allergy**: Rosario Ortiz has a known severe allergy to Aspirin (anaphylaxis). Document: Allergen=Aspirin, Reaction=Anaphylaxis, Severity=Severe.
2. **Vitals**: Record admission vitals — BP 148/90 mmHg, Weight 87 kg, Pulse 92 bpm, Temperature 37.4 C.
3. **Condition**: Add Chronic kidney disease (stage 3a) as a Confirmed condition — it is currently absent from her problem list and affects anticoagulant dosing.

## Difficulty: hard

Exact target values are provided. The agent must navigate the EHR to find the correct forms and submit the data correctly without being told which menus or buttons to use.

## Success Criteria

| Criterion | Points | Partial |
|-----------|--------|---------|
| Aspirin allergy with Anaphylaxis reaction and Severe severity | 33 | 15 pts if allergen found but incomplete |
| All 4 vitals within ±5% of target values | 34 | 7-20 pts for partial vitals |
| CKD/kidney condition added as Confirmed | 33 | None |
| **Total** | **100** | **Pass threshold: 67** |

## Verification Strategy

- **Allergy**: `GET /allergy?patient=UUID` — checks `allergen.codedAllergen.display` for "aspirin", `severity.display` for "severe", `reactions[].reaction.display` for "anaphylaxis".
- **Vitals**: `GET /obs?patient=UUID&concept=CONCEPT_UUID` — checks systolic BP (5085AAA, 140-156), weight (5089AAA, 82-92 kg), pulse (5087AAA, 84-100), temperature (5088AAA, 37.1-37.7 C) after task start timestamp.
- **Condition**: `GET /condition?patient=UUID` — checks condition display name for keywords: "kidney", "renal", "ckd", "nephropathy", "chronic kidney"; verifies `auditInfo.dateCreated >= task_start`.

## Edge Cases

- The agent may search for "Chronic kidney disease" under different names; verifier accepts any CKD/renal keyword.
- Aspirin may appear as "acetylsalicylic acid" — verifier checks for "aspirin" in both coded and non-coded allergen fields.
- Vitals accept ±5% tolerance band to account for rounding.
