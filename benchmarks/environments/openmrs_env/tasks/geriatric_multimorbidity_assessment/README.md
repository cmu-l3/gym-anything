# geriatric_multimorbidity_assessment

## Domain Context

Clinical Nurse Specialists on geriatric wards manage complex, multi-morbidity patients admitted from skilled nursing facilities. Admission assessments require coordinated documentation of vitals, updated problem lists, and initiation of appropriate medication orders — all within an active visit.

## Patient

**Corie Bergnaum** (DOB: 1925-02-04) — 101-year-old female transferred from a skilled nursing facility for evaluation of functional decline and recurrent falls.

## Goal

Complete three nursing documentation tasks during the admission assessment:

1. **Vitals**: Record admission vital signs — BP 162/88 mmHg, Weight 62 kg, Pulse 72 bpm, Temperature 36.8 C.
2. **Condition**: Add Migraine (or Chronic migraine with aura) as a Confirmed condition — currently absent from her problem list.
3. **Medication order**: Place an order for Acetaminophen (any strength/form) as the preferred analgesic.

## Difficulty: hard

Exact target values are provided. The agent must navigate the EHR to find the correct forms without being told which menus or buttons to use.

## Success Criteria

| Criterion | Points | Partial |
|-----------|--------|---------|
| All 4 vitals within acceptable range | 33 | 7-15 pts for 1-3 vitals present |
| Migraine condition added as Confirmed | 34 | None |
| Acetaminophen drug order placed | 33 | None |
| **Total** | **100** | **Pass threshold: 67** |

## Verification Strategy

- **Vitals**: `GET /obs?patient=UUID&concept=CONCEPT_UUID` — checks systolic BP (5085AAA, 154-170), weight (5089AAA, 57-67 kg), pulse (5087AAA, 64-80), temperature (5088AAA, 36.5-37.1 C) after task start.
- **Condition**: `GET /condition?patient=UUID` — checks display name for "migraine" or "headache"; verifies `auditInfo.dateCreated >= task_start`.
- **Medication**: `GET /order?patient=UUID&limit=100` — checks `drug.display` or `concept.display` for "acetaminophen", "paracetamol", or "tylenol"; verifies `dateActivated >= task_start`.

## Edge Cases

- Acetaminophen may be listed under "Paracetamol" in some OpenMRS concept dictionaries — verifier accepts all brand/generic names.
- Migraine may appear as "Migraine disorder" or "Headache" — verifier uses substring matching.
- An active visit is pre-created; the agent does not need to start one.
