# metabolic_syndrome_complication

## Domain Context

Registered Nurses in endocrinology clinics coordinate metabolic syndrome management visits, which include vital sign documentation, problem list updates for newly threshold-crossing diagnoses (such as clinical obesity), and scheduling follow-up for lab review and medication adjustment.

## Patient

**Yolando Flatley** (DOB: 1960-02-10) — 66-year-old male presenting for metabolic syndrome management. History of hypertension and hyperlipidemia; weight has increased significantly since last visit.

## Goal

Complete three nursing documentation tasks for this endocrinology visit:

1. **Vitals**: Record today's clinic vitals — BP 158/96 mmHg, Weight 102 kg, Pulse 78 bpm, Temperature 37.0 C.
2. **Condition**: Add Obesity as a Confirmed condition — patient now meets BMI threshold for clinical obesity; absent from problem list.
3. **Appointment**: Schedule an endocrinology follow-up appointment within the next 21 days.

## Difficulty: hard

Exact target values are provided. The agent must navigate the EHR to find the correct forms without being told which menus or buttons to use.

## Success Criteria

| Criterion | Points | Partial |
|-----------|--------|---------|
| All 4 vitals within acceptable range | 33 | 7-15 pts for 1-3 vitals present |
| Obesity condition added as Confirmed | 34 | None |
| Follow-up appointment within 21 days | 33 | None |
| **Total** | **100** | **Pass threshold: 67** |

## Verification Strategy

- **Vitals**: `GET /obs?patient=UUID&concept=CONCEPT_UUID` — checks systolic BP (5085AAA, 150-166), weight (5089AAA, 97-107 kg), pulse (5087AAA, 70-86), temperature (5088AAA, 36.7-37.3 C) after task start.
- **Condition**: `GET /condition?patient=UUID` — checks display name for "obes", "overweight", or "bmi"; verifies `auditInfo.dateCreated >= task_start`.
- **Appointment**: `GET /appointment?patientUuid=UUID` — checks total appointment count increased, or finds appointment with startDateTime within 21-day window from task start.

## Edge Cases

- Obesity may appear as "Obesity (finding)" or "Overweight/Obesity" — verifier uses substring matching.
- Appointment scheduling window is checked against the task start time (not current date at verification); appointments can be scheduled for any date within 21 days.
- An active visit is pre-created; the agent does not need to start one.
