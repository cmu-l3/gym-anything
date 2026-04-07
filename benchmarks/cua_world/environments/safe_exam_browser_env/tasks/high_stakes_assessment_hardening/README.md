# Task: high_stakes_assessment_hardening

## Domain Context

**Occupation**: Certification Program Manager / Financial Examiner (O*NET 13-1041.00)
**Industry**: Financial Services / Professional Testing
**Software**: SEB Server v2.2 — used by professional certification bodies to manage
high-stakes credential examinations requiring maximum browser lockdown.

> Note: Safe Exam Browser has no occupation rows in master_dataset.csv. Task based on
> domain knowledge: CPA exam boards use SEB Server to enforce strict security for
> Uniform CPA Examination sessions.

Real Certification Program Managers use SEB Server to create purpose-specific exam
configurations with distinct security profiles. A CPA exam requires a different
configuration than a practice quiz — maximum lockdown, all secondary monitoring
channels enabled, and clearly named entities for audit trail purposes.

---

## Task Overview

The State Board of Accountancy received a complaint about unauthorized resource access
during a recent exam session. In response, the security committee mandated creation of a
hardened configuration suite: a named exam configuration, a purpose-built connection
configuration, and an exam template with two independent monitoring indicators calibrated
to a 4-hour exam session.

---

## Goal (End State)

| Entity | Required Name | Key Properties |
|--------|--------------|----------------|
| Exam Configuration | `CPA Board Exam - Maximum Security` | type = EXAM_CONFIG, new entity |
| Connection Configuration | `CPA Exam Connection` | new entity |
| Exam Template | `CPA Board Exam Template` | new entity |
| Indicator 1 (on template) | `Connection Monitor` | type = LAST_PING_TIME |
| Indicator 2 (on template) | `Security Alert Monitor` | type = ERROR_LOG_COUNTER |

---

## Difficulty Justification (very_hard)

- Agent must create **5 distinct entities** of 4 different types
- Agent must navigate three separate sections of SEB Server (Configurations > Exam Config,
  Configurations > Connection Config, Exam Administration > Exam Template)
- Adding two indicators to a template requires: save template first, then locate
  the Indicators section, add each indicator individually with specific type selection
- Indicator type names in the dropdown are domain-specific (agent must identify which
  type maps to "Error-Log Counter")
- No UI path provided — agent must explore the application hierarchy independently
- Max steps: 90, timeout: 720s

---

## Scoring Breakdown

| Criterion | Points | What is Checked |
|-----------|--------|-----------------|
| C1 | 25 | `configuration_node` named `CPA Board Exam - Maximum Security` with type=EXAM_CONFIG, new (delta > 0) |
| C2 | 25 | `seb_client_configuration` named `CPA Exam Connection` exists |
| C3 | 25 | `exam_template` named `CPA Board Exam Template` exists |
| C4 | 25 | Template has 2 indicators: `Connection Monitor` (PING type) + `Security Alert Monitor` (ERROR type) |

**Pass threshold**: 75/100

Partial credit:
- C1: 15pts if exists but may be pre-existing
- C4: 15pts if two indicators exist with correct types but wrong names; 8pts if only 1 indicator

---

## Verification Strategy

### Export script queries:
- `configuration_node` WHERE name='CPA Board Exam - Maximum Security' AND type='EXAM_CONFIG'
- `seb_client_configuration` WHERE name='CPA Exam Connection'
- `exam_template` WHERE name='CPA Board Exam Template'
- `indicator` WHERE exam_template_id={tmpl_id}: id, name, type for all indicators

### Do-nothing invariant:
- total_new = 0 → gate → score=0, passed=False ✓

---

## Database Schema Reference

| Table | Key Columns | Notes |
|-------|-------------|-------|
| `configuration_node` | id, name, description, type | type='EXAM_CONFIG' for exam configurations |
| `seb_client_configuration` | id, name, active | Connection configs; must activate separately |
| `exam_template` | id, name, description | Templates for standardizing exam settings |
| `indicator` | id, name, type, exam_template_id | type values: LAST_PING_TIME, ERROR_LOG_COUNTER, WARNING_LOG_COUNTER, INFO_LOG_COUNTER, BATTERY_STATUS |

---

## Edge Cases

1. **Agent creates only exam config + connection config** (skips template/indicators): score = 50, fails
2. **Agent adds only 1 indicator**: C4 = 8pts, total ≈ 58, fails
3. **Agent uses wrong indicator type** (e.g., INFO_LOG_COUNTER instead of ERROR_LOG_COUNTER): partial credit
4. **Agent names indicators differently**: type-only check gives partial (15/25 for C4)
