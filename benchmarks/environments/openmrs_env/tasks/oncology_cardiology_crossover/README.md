# oncology_cardiology_crossover

## Domain Context

Clinical Nurse Specialists in cardio-oncology units manage patients at the intersection of cancer therapy and cardiac risk. Safety documentation before imaging (contrast allergy flagging), vital sign monitoring for cardiac toxicity, and scheduling of follow-up visits are core nursing responsibilities in joint cardio-oncology clinics.

## Patient

**Mateo Matias** (DOB: 1946-07-19) — 79-year-old male with metastatic prostate cancer on androgen deprivation therapy and a history of myocardial infarction and aortic regurgitation, presenting to a joint cardio-oncology clinic.

## Goal

Complete three nursing documentation tasks for this cardio-oncology evaluation:

1. **Allergy**: Mateo Matias experienced urticaria (hives) during a prior CT scan with iodinated contrast. Document: Allergen=Iodinated contrast media, Reaction=Urticaria, Severity=Moderate.
2. **Vitals**: Record today's cardio-oncology vitals — BP 128/78 mmHg, Weight 72 kg, Pulse 66 bpm, Temperature 37.2 C.
3. **Appointment**: Schedule a cardio-oncology follow-up appointment within the next 28 days.

## Difficulty: hard

Exact target values are provided. The agent must navigate the EHR to find the correct forms without being told which menus or buttons to use.

## Success Criteria

| Criterion | Points | Partial |
|-----------|--------|---------|
| Contrast allergy with Urticaria reaction and Moderate severity | 33 | 15 pts if allergen found but incomplete |
| All 4 vitals within acceptable range | 34 | 8-17 pts for 1-3 vitals present |
| Follow-up appointment within 28 days | 33 | None |
| **Total** | **100** | **Pass threshold: 67** |

## Verification Strategy

- **Allergy**: `GET /allergy?patient=UUID` — checks `allergen.codedAllergen.display` for "contrast", "iodine", or "iodinated"; checks `severity.display` for "moderate"; checks `reactions[].reaction.display` for "urticaria", "hive", "rash", or "wheals".
- **Vitals**: `GET /obs?patient=UUID&concept=CONCEPT_UUID` — checks systolic BP (5085AAA, 120-136), weight (5089AAA, 67-77 kg), pulse (5087AAA, 58-74), temperature (5088AAA, 36.9-37.5 C) after task start.
- **Appointment**: `GET /appointment?patientUuid=UUID` — checks total appointment count increased, or finds appointment with startDateTime within 28-day window from task start.

## Edge Cases

- Iodinated contrast may be listed as "Iodine", "Contrast dye", or "Radiocontrast media" — verifier uses substring matching for "contrast", "iodine", "iodinated".
- Urticaria may appear as "Hives", "Urticarial rash", or "Wheals" — verifier accepts any of these.
- An active visit is pre-created; the agent does not need to start one.
