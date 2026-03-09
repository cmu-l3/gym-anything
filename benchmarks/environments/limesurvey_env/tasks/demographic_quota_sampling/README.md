# Task: Demographic Quota-Controlled Consumer Panel Study

## Domain Context

Market research analysts running consumer panel studies must ensure representative sampling across demographic segments. **Quota management** is a core LimeSurvey feature that stops collecting responses from a demographic group once the target count is reached — preventing over-representation of any single group. Setting up interlocking quotas (gender × age-range) is a standard professional workflow in quantitative market research, equivalent to what GfK, Nielsen, and Ipsos analysts do daily.

## Occupation Context (from master_dataset.csv)
- **Market Research Analysts and Marketing Specialists** (SOC 13-1161, product_gdp_usd=$25M): "Primary tool for gathering proprietary market data and consumer feedback"
- **Meeting, Convention, and Event Planners** (SOC 13-1121): "Used for collecting post-event feedback and registration data" — quota management also applies to event registration

## Task Goal

Configure 4 interlocking demographic quotas on the pre-built consumer electronics survey:
1. "Young Male" — GENDER=Male AND AGE_RANGE=18-34, limit 25
2. "Young Female" — GENDER=Female AND AGE_RANGE=18-34, limit 25
3. "Mid-Age Male" — GENDER=Male AND AGE_RANGE=35-54, limit 25
4. "Mid-Age Female" — GENDER=Female AND AGE_RANGE=35-54, limit 25

## Real Data Used

Consumer electronics survey structure based on **GfK Consumer Electronics Study** methodology and **Nielsen Connected Consumer Report** questionnaire design — standard industry approaches to measuring electronics purchase behavior and brand preferences with demographic quota controls.

The survey questions cover:
- Respondent profile (gender, age, country)
- Purchase categories in last 12 months (multi-choice, 8 categories from smartphones to wearables)
- Annual spend estimates
- Purchase factor rankings (price, brand, specs, design, ecosystem, reviews)
- Brand preference ratings (Apple, Samsung, Sony, LG, Microsoft)

## Verification Strategy

1. **4 quotas created** (25 pts): `SELECT COUNT(*) FROM lime_quota WHERE sid=X` — need >= 4
2. **Quota limits = 25** (25 pts): `SELECT COUNT(*) FROM lime_quota WHERE sid=X AND qlimit=25` — all 4 must have limit 25
3. **Linked to GENDER question** (25 pts): `SELECT COUNT(DISTINCT quota_id) FROM lime_quota_members qm JOIN lime_quota lq ON qm.quota_id=lq.id WHERE lq.sid=X AND qm.qid=<GENDER_QID>` — need >= 2 quotas linked
4. **Linked to AGE_RANGE question** (25 pts): Same as above but for `<AGE_QID>` — need >= 2 quotas linked

Pass threshold: 70/100

## Schema Reference

```sql
-- List all quotas for a survey
SELECT id, name, qlimit, action FROM lime_quota WHERE sid=X;

-- Check which question/answer each quota is linked to
SELECT qm.quota_id, qm.qid, qm.code FROM lime_quota_members qm
JOIN lime_quota lq ON qm.quota_id=lq.id WHERE lq.sid=X;

-- Check GENDER and AGE_RANGE question IDs
SELECT qid, title FROM lime_questions WHERE sid=X AND parent_qid=0 AND title IN ('GENDER','AGE_RANGE');

-- Quota names
SELECT id, name, qlimit FROM lime_quota WHERE sid=X ORDER BY id;
```

## Edge Cases
- LimeSurvey quotas require the survey to have ACTIVE status for quota actions to apply during live data collection; however, the quota records can be created while the survey is inactive
- Each quota member entry links one quota to one specific answer option on one question — so a quota with 2 conditions (gender AND age) will have 2 entries in lime_quota_members
- The `action` field on quotas: 0=soft quota (continue), 1=hard quota (terminate), 2=confirm (ask respondent)
