# Task: multi_role_department_provisioning

## Domain Context

**Occupation**: Information Security Analyst (O*NET 15-1212.00)
**Industry**: Higher Education / Information Technology
**Software**: SEB Server v2.2 — used by university IT security teams to manage
role-based access for exam administrators, supporters, and institutional supervisors.

> Note: Safe Exam Browser has no occupation rows in master_dataset.csv. Task based on
> domain knowledge: large universities' IT security teams provision SEB Server for
> multi-department deployments with carefully controlled role separation.

Real Information Security Analysts use SEB Server's user management to implement
least-privilege access: Exam Supporters can only assist during live sessions,
Exam Administrators can create and manage exams, and Institutional Administrators
have cross-institution visibility. Getting these roles right is a security requirement.

---

## Task Overview

Crestwood University is onboarding three academic departments to the centralized SEB Server.
Each department nominated a representative with a specific operational role. The IT Security
Administrator must create 4 user accounts with distinct roles and a shared connection
configuration for all departments.

The critical complexity: **three distinct role types** must be assigned correctly across
four accounts, plus a connection configuration must be created and activated.

---

## Goal (End State)

| Username | Full Name | Email | Required Role |
|----------|-----------|-------|---------------|
| `cs.admin` | Elena Vasquez | e.vasquez@cs.crestwood.edu | EXAM_ADMIN |
| `math.admin` | Robert Chen | r.chen@math.crestwood.edu | EXAM_ADMIN |
| `physics.supporter` | Aisha Okonkwo | a.okonkwo@physics.crestwood.edu | EXAM_SUPPORTER |
| `it.supervisor` | Marcus Webb | m.webb@it.crestwood.edu | INSTITUTIONAL_ADMIN |

Plus: Connection config `Department Hub Connection Config` exists and is active.

All 4 accounts must be activated.

---

## Difficulty Justification (very_hard)

- Creating **4 separate user accounts** requires repeated navigation through the user
  creation form — high step count
- **Three different role types** must be selected correctly:
  - EXAM_ADMIN × 2 (cs.admin, math.admin)
  - EXAM_SUPPORTER × 1 (physics.supporter) — agent must NOT promote this to EXAM_ADMIN
  - INSTITUTIONAL_ADMIN × 1 (it.supervisor) — highest privilege, carefully controlled
- Each account must be individually **activated** after creation (separate action)
- Connection config creation is a separate workflow in a different section
- No UI hints — agent must find User Account section, understand role dropdown options,
  and know to activate each account
- Max steps: 100, timeout: 800s

---

## Scoring Breakdown

| Criterion | Points | What is Checked |
|-----------|--------|-----------------|
| C1 | 20 | `user` count delta >= 3 (at least 3 new accounts created) |
| C2 | 30 | All 4 usernames present: cs.admin, math.admin, physics.supporter, it.supervisor |
| C3 | 25 | Correct role for each: cs.admin+math.admin→EXAM_ADMIN, physics.supporter→EXAM_SUPPORTER, it.supervisor→INSTITUTIONAL_ADMIN |
| C4 | 25 | `seb_client_configuration` named `Department Hub Connection Config` exists and active |

**Pass threshold**: 75/100

Partial credit:
- C1: 15pts for 3 accounts, 8pts for 1-2 accounts
- C2: 20pts for 3/4, 12pts for 2/4, 5pts for 1/4
- C3: 18pts for 3/4 correct, 10pts for 2/4, 5pts for 1/4
- C4: 15pts if config exists but not activated

---

## Verification Strategy

### Export script queries:
- `user` WHERE username IN ('cs.admin','math.admin','physics.supporter','it.supervisor'): each individually
- `user_role` WHERE user_id={uid}: for each found user
- `seb_client_configuration` WHERE name='Department Hub Connection Config': id, active

### Do-nothing invariant:
- new_users_created=0, new_connection_configs_created=0 → gate → score=0 ✓

---

## Database Schema Reference

| Table | Key Columns | Notes |
|-------|-------------|-------|
| `user` | id, username, name, surname, email, active | All 4 must have active=1 |
| `user_role` | user_id, user_role | Role values: EXAM_ADMIN, EXAM_SUPPORTER, INSTITUTIONAL_ADMIN |
| `seb_client_configuration` | id, name, active | active=1 means activated via action button |

---

## Edge Cases

1. **Agent assigns all 4 users EXAM_ADMIN**: C3 = partial (10/25, only 2 correct)
2. **Agent creates 3 of 4 accounts**: C1 passes partial (15), C2 partial (20), C3 partial based on what's done
3. **Agent creates connection config but forgets to activate it**: C4 = 15/25, total ≈ 60-65, fails
4. **Agent uses wrong username spelling** (e.g., "cs_admin" vs "cs.admin"): that account fails all checks
