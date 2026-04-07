# Task: medical_licensing_exam_workflow

## Domain Context

**Occupation**: Medical and Health Services Manager (O*NET 11-9111.00)
**Industry**: Healthcare / Medical Education / Licensing
**Software**: SEB Server v2.2 — used by medical licensing boards to administer
USMLE-style preparation assessments with proctored browser control.

> Note: Safe Exam Browser has no occupation rows in master_dataset.csv. Task based on
> domain knowledge: medical licensing boards and teaching hospitals use SEB Server for
> board preparation and certification examination sessions.

Real Medical Education Technology Specialists use SEB Server's Assessment Tool integration
to import exam content from LMS platforms, then configure per-exam monitoring to detect
connection issues and exam integrity violations.

---

## Task Overview

A regional testing center for the National Board of Medical Examiners needs to onboard
a new USMLE Step 1 preparation exam cycle. The IT specialist must: import an exam from
the already-connected Assessment Tool, configure two monitoring indicators directly on
that imported exam (not on a template — per-exam monitoring for this cycle only), and
create a dedicated proctor account for the session.

**Key distinction from other tasks**: indicators are added to the **imported exam directly**,
not to an exam template. This tests knowledge of SEB Server's dual indicator placement
(indicators can live on templates for reuse, or on individual exams for one-off sessions).

---

## Goal (End State)

| Entity | Required Properties |
|--------|---------------------|
| Imported exam | New exam in `exam` table (count delta > 0 from baseline) |
| Indicator 1 (on exam) | name = `Latency Monitor`, type = LAST_PING_TIME, linked to imported exam |
| Indicator 2 (on exam) | name = `Integrity Alert`, type = WARNING_LOG_COUNTER, linked to imported exam |
| User account | username = `med.proctor`, active=1, role = EXAM_SUPPORTER |

---

## Difficulty Justification (very_hard)

- Agent must first **locate and use the Assessment Tool import** workflow — not obvious
  (hidden under Exam Administration, requires clicking "Import from Assessment Tool" or
  similar, then browsing available quizzes)
- After import, agent must **navigate to the imported exam** and add indicators to IT
  specifically (not to a template), which requires knowing the exam detail view
- Two indicators of **different types** must be added — agent must select the correct
  type from the dropdown (WARNING_LOG_COUNTER vs ERROR_LOG_COUNTER)
- A new user must be created with EXAM_SUPPORTER (not EXAM_ADMIN) role
- No UI hints provided — agent must explore all workflows independently
- Max steps: 90, timeout: 720s

---

## Scoring Breakdown

| Criterion | Points | What is Checked |
|-----------|--------|-----------------|
| C1 | 20 | `exam` count delta > 0 (at least one exam imported) |
| C2 | 30 | Indicators on newly imported exam: 1 LAST_PING_TIME (`Latency Monitor`) + 1 WARNING_LOG_COUNTER (`Integrity Alert`) |
| C3 | 25 | `user` WHERE username='med.proctor' exists AND active=1 |
| C4 | 25 | `user_role` WHERE user_id={uid} contains EXAM_SUPPORTER |

**Pass threshold**: 70/100

Partial credit:
- C2: 20pts if 2 indicators with correct types but wrong names; 12pts if 2 indicators wrong types; 8pts if only 1
- C3: 12pts if user exists but not activated
- C4: 8pts if user exists but has wrong role

---

## Verification Strategy

### Export script queries:
- `exam` COUNT(*) vs baseline to detect import
- `exam` ORDER BY id DESC to get new exam IDs
- `indicator` WHERE exam_id={new_exam_id}: id, name, type
- `user` WHERE username='med.proctor': id, active
- `user_role` WHERE user_id={uid}: user_role

### Do-nothing invariant:
- new_exams_imported=0, new_indicators_created=0, new_users_created=0 → total_new=0 → gate → score=0 ✓

---

## Assessment Tool Context

The SEB Server demo environment includes a pre-configured Testing/Mock LMS with
8 importable quizzes. The agent can import any one of them. The verifier accepts
any newly created exam (identified by count delta), not a specific named exam.

---

## Database Schema Reference

| Table | Key Columns | Notes |
|-------|-------------|-------|
| `exam` | id, external_id, status | Imported exams; status typically RUNNING or FINISHED |
| `indicator` | id, name, type, exam_id, exam_template_id | Both exam_id and exam_template_id exist; for per-exam: exam_id is set |
| `user` | id, username, name, surname, email, active | active=1 required |
| `user_role` | user_id, user_role | EXAM_SUPPORTER for proctors |

---

## Edge Cases

1. **Agent adds indicators to a template instead of the exam**: exam_id on indicators will be NULL → C2 fails
2. **Agent imports exam but forgets indicators**: C1 passes (20), C2 fails (0), total = 45, fails
3. **Agent creates user with EXAM_ADMIN instead of EXAM_SUPPORTER**: C3 passes (25), C4 partial (8)
4. **Agent imports multiple exams**: verifier checks indicators on ANY of the new exam IDs
