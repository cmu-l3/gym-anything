# Task: full_semester_exam_rollout

## Domain Context

**Occupation**: Postsecondary Education Administrator (O*NET 11-9033.00)
**Industry**: Higher Education
**Software**: SEB Server v2.2 — the server-side management console for Safe Exam Browser,
used by universities to configure and monitor secure online examinations.

> Note: Safe Exam Browser has no occupation rows in master_dataset.csv (Assessment category
> only, $10.6B total GDP). Task design is based on domain knowledge of SEB Server deployments
> in higher education institutions.

Real Postsecondary Education Administrators use SEB Server to provision and maintain the
institutional exam infrastructure: connection configurations define how students connect
to exam sessions, exam templates standardize monitoring settings across departments, and
user accounts control who can administer vs. support exams.

---

## Task Overview

Whitmore University is transitioning all final examinations to Safe Exam Browser. The IT
admin for the Office of Academic Integrity must provision four inter-related components
before the finals period:

1. A **connection configuration** that governs how student browsers connect to the exam server
2. An **exam template** that standardizes monitoring settings across all final exams
3. A **monitoring indicator** on the template to track real-time connection health
4. A **user account** for the new examination coordinator with appropriate administrative access

---

## Goal (End State)

The SEB Server database must contain all of the following as **new** entities (not pre-existing):

| Entity | Required Name | Key Properties |
|--------|--------------|----------------|
| Connection Configuration | `Finals Week Secure Config` | active=true, fallback URL contains `whitmore.edu` |
| Exam Template | `Final Examination Template` | description set |
| Indicator (on template) | `Network Quality Monitor` | type = `LAST_PING_TIME` |
| User Account | `exam.coordinator` | active=true, role = EXAM_ADMIN |

---

## Difficulty Justification (very_hard)

- Agent receives only the **goal** — no UI path, no navigation steps
- Agent must independently discover: where connection configs live (Configurations menu),
  where exam templates live (Exam Administration menu), how to add indicators to a template
  (separate action after template creation), and how to activate a user account
- Requires understanding SEB Server's domain model: connection configs are separate from
  exam configs, templates are separate from active exams, users have roles not permissions
- 4 independent entities must be created with specific names — no partial shortcuts
- Max steps: 90 (equivalent to 12 min), timeout: 720s

---

## Scoring Breakdown

| Criterion | Points | What is Checked |
|-----------|--------|-----------------|
| C1 | 25 | `seb_client_configuration` row named `Finals Week Secure Config` exists, active, fallback URL contains `whitmore.edu` or `exams` |
| C2 | 25 | `exam_template` row named `Final Examination Template` exists AND new (delta > 0) |
| C3 | 25 | `indicator` row named `Network Quality Monitor` of type containing `PING` linked to the template |
| C4 | 25 | `user` row with username `exam.coordinator` active=1, `user_role` containing `EXAM_ADMIN` |

**Pass threshold**: 75/100 (3 of 4 criteria must be fully met)

Partial credit:
- C1: 15pts if config exists but not activated; 10pts if wrong fallback URL
- C2: 15pts if template found but appears pre-existing
- C3: 15pts if LAST_PING_TIME indicator exists but wrong name; 10pts if wrong type
- C4: 15pts if user exists but not activated or wrong role

---

## Verification Strategy

### Export script queries:
- `seb_client_configuration` WHERE name = 'Finals Week Secure Config': id, active, fallback_start_url
- `exam_template` WHERE name = 'Final Examination Template': id, description
- `indicator` WHERE exam_template_id = {tmpl_id}: id, name, type
- `user` WHERE username = 'exam.coordinator': id, active
- `user_role` WHERE user_id = {uid}: user_role

All counts compared against baseline recorded at task start.

### Do-nothing invariant:
- All `new_*_created` fields = 0 → gate triggers → score=0, passed=False ✓

---

## Database Schema Reference

| Table | Key Columns | Notes |
|-------|-------------|-------|
| `seb_client_configuration` | id, name, active, fallback_start_url | Connection configs; active=1 means activated |
| `exam_template` | id, name, description | Exam templates; created via Exam Administration |
| `indicator` | id, name, type, exam_id, exam_template_id | Monitoring indicators; linked by FK |
| `user` | id, username, name, surname, email, active | User accounts |
| `user_role` | user_id, user_role | Role junction table; values: EXAM_ADMIN, EXAM_SUPPORTER, INSTITUTIONAL_ADMIN |

---

## Edge Cases

1. **Agent activates config but uses wrong fallback URL**: C1 gives partial credit (15/25)
2. **Agent creates template but forgets to add indicator**: C2 passes (25), C3 fails (0)
3. **Agent creates user but doesn't activate**: C4 gives partial (15/25)
4. **Agent uses slightly different name** (e.g., "Final Exam Template"): name mismatch → criterion fails
5. **Pre-existing entity with same name**: baseline delta = 0 → C2 gives partial (15/25)
