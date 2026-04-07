# multi_vacancy_recruitment_close

## Domain Context

**Occupation**: First-Line Supervisors of Office and Administrative Support Workers — talent acquisition and HR operations in corporate settings (430M GDP, top OrangeHRM user segment).

**Scenario**: Apex Analytics Group has completed the Q2 2025 hiring cycle. The hiring panel has reviewed all shortlisted candidates for two open positions and issued final decisions. The Talent Acquisition Manager must execute those decisions in OrangeHRM's Recruitment module.

---

## Goal

Read the hiring decisions memo on the Desktop. For each candidate across the two job vacancies, update their status in OrangeHRM Recruitment to match the panel's decision: "Job Offered" for approved candidates, "Rejected" for rejected candidates.

**End state**: All 4 candidates have their status updated per the memo. Marcus Webb and Danielle Osei are in "Job Offered" status. Priya Sharma and Felix Braun are in "Rejected" status.

---

## Why This is Very Hard

- Agent must navigate OrangeHRM Recruitment module (non-obvious; not covered in description)
- Two vacancies with 2 candidates each — must find each candidate under their specific vacancy
- Status workflow in OrangeHRM requires specific action buttons (not a simple dropdown)
- Description gives only the high-level goal; agent must discover the Recruitment → Vacancies → Candidates path

---

## Candidates and Expected Outcomes

| Candidate | Vacancy | Decision |
|-----------|---------|----------|
| Marcus Webb | Senior Data Analyst - Q2 2025 | Job Offered |
| Priya Sharma | Senior Data Analyst - Q2 2025 | Rejected |
| Danielle Osei | Clinical Coordinator - Q2 2025 | Job Offered |
| Felix Braun | Clinical Coordinator - Q2 2025 | Rejected |

---

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Marcus Webb → Job Offered | 25 |
| Priya Sharma → Rejected | 25 |
| Danielle Osei → Job Offered | 25 |
| Felix Braun → Rejected | 25 |
| **Total** | **100** |

Partial credit (5 pts): candidate advanced beyond Shortlisted but not to the correct target status.

**Pass threshold**: 65

---

## Strategy Enumeration (Anti-Pattern 13 check)

| Strategy | Marcus | Priya | Danielle | Felix | Total | Pass? |
|----------|--------|-------|----------|-------|-------|-------|
| Do-nothing (all Shortlisted) | 0 | 0 | 0 | 0 | 0 | No |
| Mass-advance all to "Job Offered" | 25 | 5(partial) | 25 | 5(partial) | 60 | No (< 65) ✓ |
| Mass-reject all | 5(partial) | 25 | 5(partial) | 25 | 60 | No (< 65) ✓ |
| Correct: 2 Offered + 2 Rejected | 25 | 25 | 25 | 25 | 100 | Yes ✓ |
| 3 correct decisions | — | — | — | — | 75 | Yes ✓ |

---

## Verification Strategy

**export_result.sh** queries `ohrm_job_candidate` by first/last name, also queries `ohrm_job_candidate_status` for the actual status labels at runtime (status IDs can vary across OrangeHRM installs).

**verifier.py** uses both the numeric status_id and the label string (checking for 'offer' / 'reject' substrings) to allow for slight variations in status naming.

---

## Setup State

`setup_task.sh`:
1. Deletes any prior Marcus/Priya/Danielle/Felix candidates
2. Creates 2 vacancies (Senior Data Analyst - Q2 2025, Clinical Coordinator - Q2 2025)
3. Creates 4 candidates in "Shortlisted" status under their respective vacancies
4. Creates `/home/ga/Desktop/q2_hiring_decisions.txt` with the decisions memo

---

## Schema Reference

```sql
ohrm_job_vacancy:
  id               INT
  name             VARCHAR
  job_title_code   INT  (FK → ohrm_job_title.id)
  hiring_manager_id INT (FK → hs_hr_employee.emp_number)
  status           INT  (1=Active, 2=Filled, 3=Closed)

ohrm_job_candidate:
  id               INT
  first_name       VARCHAR
  last_name        VARCHAR
  email            VARCHAR
  status           INT  (FK → ohrm_job_candidate_status.id)
  vacancy_id       INT  (FK → ohrm_job_vacancy.id)

ohrm_job_candidate_status:
  id               INT
  status_label     VARCHAR  ('Application Initiated', 'Shortlisted', 'Rejected', 'Job Offered', ...)
```

---

## Edge Cases

- Status IDs are not hardcoded — export_result.sh looks them up from `ohrm_job_candidate_status` with a label-match
- OrangeHRM recruitment pipeline requires clicking specific action buttons (e.g., "Shortlist", "Offer Job", "Reject") — not a simple status dropdown
- Verifier accepts any label containing 'offer' or 'reject' (case-insensitive)
