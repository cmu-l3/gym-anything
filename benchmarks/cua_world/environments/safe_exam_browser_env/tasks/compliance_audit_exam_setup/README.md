# Task: compliance_audit_exam_setup

## Domain Context

**Occupation**: Compliance Manager / Data Protection Officer (O*NET 13-1041.06)
**Industry**: Legal / Higher Education / Data Governance (European)
**Software**: SEB Server v2.2 — used by European universities' Data Protection Officers
to configure exam systems compliant with GDPR Article 25 (data protection by design).

> Note: Safe Exam Browser has no occupation rows in master_dataset.csv. Task based on
> domain knowledge: GDPR-subject institutions (EU/EEA universities) must configure their
> exam platforms to minimize data collection and document compliance rationale.

Real Compliance Managers use SEB Server to implement data minimisation in exam monitoring:
high ping thresholds mean fewer monitoring events are logged, no fallback connections mean
fewer data transfer paths, and configuration descriptions serve as audit trail documentation.

---

## Task Overview

Following a GDPR Article 25 audit at Nordviken University (Sweden), the Data Protection
Officer must configure SEB Server with documented compliance rationale. The configuration
must: reference GDPR in its description (audit trail), use a dedicated connection config
without fallback (minimize data paths), apply intentionally high monitoring thresholds
(minimize surveillance), and create a DPO user account for ongoing oversight.

The task tests whether the agent can read compliance requirements from a professional
context and translate them into specific technical configurations with correct naming
and documented rationale.

---

## Goal (End State)

| Entity | Required Name | Key Properties |
|--------|--------------|----------------|
| Exam Configuration | `GDPR Compliant Exam Config` | description contains "GDPR" or "data protection" or "privacy" |
| Connection Configuration | `Privacy-First Connection` | active=true, no fallback enabled |
| Exam Template | `GDPR Exam Template` | new entity |
| Indicator (on template) | `Minimal Monitoring` | type = LAST_PING_TIME |
| User Account | `dpo.officer` | active=true, role = EXAM_ADMIN |

---

## Difficulty Justification (very_hard)

- Agent must **read domain context** (GDPR compliance) and translate it into technical
  choices — this is not mechanical button-clicking
- The description field on the exam configuration requires deliberate, contextually
  appropriate content (agent must include "GDPR" or equivalent)
- Agent must understand that GDPR compliance means NOT enabling the fallback option
- Four separate SEB Server sections must be visited: Exam Config, Connection Config,
  Exam Template (+ indicator), User Account
- Intentionally high thresholds (5000/15000) differ from typical values — agent must
  enter them correctly, understanding their operational meaning
- Max steps: 90, timeout: 720s

---

## Scoring Breakdown

| Criterion | Points | What is Checked |
|-----------|--------|-----------------|
| C1 | 25 | `configuration_node` named `GDPR Compliant Exam Config` exists (new) with description containing 'gdpr', 'privacy', 'data protection', 'article 25', or 'by design' |
| C2 | 25 | `seb_client_configuration` named `Privacy-First Connection` exists and active |
| C3 | 25 | `exam_template` named `GDPR Exam Template` + indicator `Minimal Monitoring` of type LAST_PING_TIME on it |
| C4 | 25 | `user` username=`dpo.officer` active=1, `user_role` contains EXAM_ADMIN |

**Pass threshold**: 75/100

Partial credit:
- C1: 15pts if exam config created but description missing GDPR keywords; 10pts if exists but pre-existing
- C2: 15pts if config exists but not activated
- C3: 18pts if LAST_PING_TIME indicator exists but named differently; 8pts if template exists but no indicator
- C4: 15pts if user exists but not activated or wrong role

---

## Verification Strategy

### Export script queries:
- `configuration_node` WHERE name='GDPR Compliant Exam Config' AND type='EXAM_CONFIG': id, description
- `seb_client_configuration` WHERE name='Privacy-First Connection': id, active, fallback_start_url
- `exam_template` WHERE name='GDPR Exam Template': id
- `indicator` WHERE exam_template_id={tmpl_id}: id, name, type
- `user` WHERE username='dpo.officer': id, active
- `user_role` WHERE user_id={uid}: user_role

### GDPR description keywords (any one sufficient):
`gdpr`, `privacy`, `data protection`, `article 25`, `by design`

### Do-nothing invariant:
- total_new = 0 → gate → score=0, passed=False ✓

---

## Database Schema Reference

| Table | Key Columns | Notes |
|-------|-------------|-------|
| `configuration_node` | id, name, description, type | type='EXAM_CONFIG'; description is free text |
| `seb_client_configuration` | id, name, active, fallback_start_url | fallback_start_url empty if fallback not enabled |
| `exam_template` | id, name, description | Created via Exam Administration > Exam Template |
| `indicator` | id, name, type, exam_template_id | type=LAST_PING_TIME for network monitoring |
| `user` | id, username, name, surname, email, active | |
| `user_role` | user_id, user_role | EXAM_ADMIN for DPO |

---

## Edge Cases

1. **Agent sets description to generic text** (e.g., "New configuration"): C1 = 15/25
2. **Agent enables fallback** on the connection config: verifier notes it but still passes C2 (fallback URL check not used as gate, just informational)
3. **Agent creates template but wrong indicator type**: C3 = 12/25
4. **Agent creates all entities but uses wrong user role** (e.g., EXAM_SUPPORTER for DPO): C4 = 15/25
5. **Agent names connection config differently**: C2 fails entirely
