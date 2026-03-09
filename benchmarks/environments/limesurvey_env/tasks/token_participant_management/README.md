# Task: Token-Based 360-Degree Leadership Feedback Survey Management

## Domain Context

Industrial-Organizational (I-O) psychologists use 360-degree feedback surveys to collect multi-rater assessments of leadership competencies from peers, direct reports, and supervisors. A critical professional requirement is that these surveys use **closed-access token authentication** — only invited raters with unique personal tokens can submit feedback, preventing data contamination and ensuring response traceability. Setting up participant lists and token-based access control is a core LimeSurvey workflow for organizational assessments.

## Occupation Context (from master_dataset.csv)
- **Industrial-Organizational Psychologists** (SOC 19-3032): "Creating and administering assessments, engagement surveys, and 360-degree feedback tools is a core function"
- **Market Research Analysts** (SOC 13-1161): "Primary tool for gathering proprietary market data" — applies to internal HR analytics

## Task Goal

Convert the pre-built "Leadership Competency Assessment 360" survey from open-access to token-controlled closed access:
1. Enable participant token management (lime_tokens table created)
2. Add 4 specific raters to the participant list
3. Customize invitation email subject to include "360-Degree Leadership Feedback"
4. Generate unique tokens for all participants

## Real Data Used

Leadership competency items adapted from the **Korn Ferry Lominger Leadership Architect** framework — an industry-standard competency model used in professional 360-degree assessments worldwide:
1. Makes timely decisions when facing uncertainty or incomplete information
2. Clearly communicates expectations and strategic priorities to the team
3. Provides meaningful developmental feedback and coaching to direct reports
4. Builds trust by consistently following through on commitments
5. Resolves interpersonal conflict constructively and with fairness
6. Demonstrates strategic perspective when making day-to-day decisions
7. Creates an environment that motivates and energizes team members
8. Takes accountability for team outcomes — both successes and setbacks
9. Actively promotes diverse perspectives and inclusive team practices
10. Drives continuous process improvement and organizational learning

## Verification Strategy

1. **Tokens enabled** (30 pts): `SHOW TABLES LIKE 'lime_tokens_SID'` — table must exist
2. **Participants added** (30 pts): `SELECT COUNT(*) FROM lime_tokens_SID` — need >= 4
3. **Correct emails present** (20 pts): Check for m.thompson, s.chen, d.okafor, p.sharma @acmecorp.com
4. **Email subject customized** (20 pts): `surveyls_email_invite_subj` contains '360-Degree Leadership Feedback'

Pass threshold: 70/100

## Schema Reference

```sql
-- Check if token table exists
SHOW TABLES LIKE 'lime_tokens_SID';

-- Count participants
SELECT COUNT(*) FROM lime_tokens_SID;

-- Check participant emails
SELECT email, token FROM lime_tokens_SID;

-- Check invitation email template
SELECT surveyls_email_invite_subj FROM lime_surveys_languagesettings
WHERE surveyls_survey_id=SID;
```
