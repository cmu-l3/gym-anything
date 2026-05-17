# recruitment_q2_pipeline_cleanup

**Difficulty:** very_hard  
**Timeout:** 720 s / 90 steps  
**Reward type:** sparse

## Domain context

Talent Acquisition Coordinators and HR Managers perform end-of-quarter pipeline hygiene to ensure the recruitment funnel is accurate before headcount reports are filed. A common session involves correcting misconfigured interview stages, archiving stale or duplicate applications, and completing the hire workflow for candidates who have accepted offers. This task bundles all four types of cleanup into a single Q2 audit.

## Goal (end state)

The agent must resolve four issues in the Recruitment module:

1. The "Technical Assessment" interview stage is currently positioned before the initial qualification stage — it should appear between First Interview and Second Interview.
2. At least one applicant has been sitting at an early stage with no activity for weeks and must be archived.
3. One candidate appears in two separate job pipelines simultaneously — the application in the less-advanced stage should be archived while the more progressed one is retained.
4. A candidate who accepted an offer at the contract stage must be advanced to "Contract Signed" and converted to an employee via the Create Employee action.

## Success criteria

| Criterion | Points |
|-----------|--------|
| C1: Technical Assessment stage sequence is between First Interview and Second Interview | 25 |
| C2: Stale applicant archived | 15 |
| C3: Duplicate resolved — earlier-stage application archived, later-stage retained | 20 |
| C3 partial: only one side correct | 10 |
| C4a: Offer-accepted candidate at Contract Signed stage | 15 |
| C4b: Candidate has an employee record created (`emp_id` set) | 25 |
| **Pass threshold** | **≥ 65** |

Maximum partial score without crossing the threshold: 10 pts (C3 one-side only).

## Verification strategy

`export_result.sh` reads via XML-RPC:
- `hr.recruitment.stage` — reads sequence of Technical Assessment, First Interview, Second Interview
- `hr.applicant` (with `active_test: False`) — reads `active` for Cameron Foster, Thomas Weber (SDS and ExpDev pipelines)
- `hr.applicant` — reads `stage_id` and `emp_id` for Sofia Martinez

Ground truth written to `/tmp/recruitment_cleanup_gt.json` by setup.

## Data notes

Setup creates: a "Senior Data Scientist" job position in R&D, the "Technical Assessment" stage at wrong sequence, three seeded applicants (Cameron Foster — stale; Thomas Weber × 2 pipelines; Sofia Martinez — ready to hire). Stage sequences are stored in gt so the verifier compares current vs. expected positions dynamically.

## Edge cases

- `hr.applicant` records are `active=False` when archived — queries must use `context: {'active_test': False}` to retrieve them.
- "Create Employee" is an Odoo wizard action triggered from the applicant form; it sets `emp_id` on the applicant record.
- The verifier reads actual First/Second Interview sequences at export time, so it is robust to any existing sequence values in the demo data.
