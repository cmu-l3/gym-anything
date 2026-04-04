# post_mi_cardiac_workup

## Domain Context

Critical Care Nurses in cardiac ICUs manage complex post-MI patients requiring coordinated documentation across allergy records, problem lists, and diagnostic workup orders. Renal function monitoring via Creatinine is standard post-contrast-exposure care in CKD patients. Problem list completeness is essential for safe medication management.

## Patient

**Jesse Becker** (DOB: 1943-02-04) — 83-year-old male admitted 48 hours ago following a non-ST elevation myocardial infarction (NSTEMI). Known aortic stenosis and chronic kidney disease.

## Goal

Complete three nursing documentation tasks during post-MI rounds:

1. **Allergy**: Jesse Becker experienced nausea and vomiting on Codeine during a prior hospitalization. Document: Allergen=Codeine, Reaction=Nausea and vomiting, Severity=Moderate.
2. **Condition**: Add Type 2 diabetes mellitus as a Confirmed condition — omitted during admission documentation and confirmed by endocrinology consult.
3. **Lab order**: Order a Creatinine (serum) lab test to monitor renal function after contrast exposure during cardiac catheterization.

## Difficulty: hard

Exact target values are provided. The agent must navigate the EHR to find the correct forms without being told which menus or buttons to use.

## Success Criteria

| Criterion | Points | Partial |
|-----------|--------|---------|
| Codeine allergy with Nausea/Vomiting reaction and Moderate severity | 33 | 15 pts if allergen found but incomplete |
| Type 2 diabetes mellitus condition added as Confirmed | 34 | None |
| Creatinine lab test ordered | 33 | None |
| **Total** | **100** | **Pass threshold: 67** |

## Verification Strategy

- **Allergy**: `GET /allergy?patient=UUID` — checks `allergen.codedAllergen.display` for "codeine", `severity.display` for "moderate", `reactions[].reaction.display` for "nausea" or "vomit".
- **Condition**: `GET /condition?patient=UUID` — checks display name for "diabet", "type 2", "t2dm", "dm2", or "type ii"; verifies `auditInfo.dateCreated >= task_start`.
- **Lab order**: `GET /order?patient=UUID&limit=100` — checks `concept.display` for "creatinine" or "serum creatinine"; verifies `dateActivated >= task_start`.

## Edge Cases

- Creatinine may be listed as "Serum Creatinine", "Creatinine, Serum", or "Renal function panel" — verifier uses substring "creatinine".
- Type 2 diabetes may appear under "Diabetes mellitus, type 2" or "T2DM" — verifier uses multiple keyword aliases.
- An active visit is pre-created; the agent does not need to start one.
