# Task: Conference Feedback Survey — Expression Manager Conditions & Branching Logic

## Domain Context

Meeting and event planners who collect post-conference feedback routinely need **conditional survey logic** to avoid showing irrelevant questions to respondents. For example, a question about "Which sessions did you enjoy most?" should only appear if the respondent actually attended sessions — otherwise the question is meaningless and annoys respondents. LimeSurvey's **Expression Manager** is the professional tool for this: it supports group-level conditions (`grelevance`) and question-level conditions (`relevance`) using a JavaScript-like expression language that references prior question responses.

This task reflects the real workflow of a conference coordinator or market research analyst who needs to branch a multi-page feedback survey based on earlier responses.

## Occupation Context (from master_dataset.csv)

- **Meeting, Convention, and Event Planners** (SOC 13-1121): "Used for collecting post-event feedback and registration data" — conditional branching is standard in event-feedback instruments
- **Market Research Analysts and Marketing Specialists** (SOC 13-1161, product_gdp_usd=$25M): "Primary tool for gathering proprietary market data and consumer feedback" — skip-patterns and conditional display are core competencies

## Task Goal

Configure conditional branching logic on the pre-built "Annual Tech Summit 2024 — Attendee Feedback" survey:

1. **Group condition** — Show the "Session Feedback" question group **only if** the respondent answered "Yes" to ATTENDED_SESSIONS. Set the group's `grelevance` expression accordingly.
2. **Question condition** — Show the IMPROVE_COMMENTS open-text question **only if** OVERALL_RATING is 6 or below (low satisfaction). Set the question's `relevance` expression accordingly.
3. **End redirect URL** — Set the survey's end-of-survey URL to `http://techsummit.example.com/thank-you` so respondents are redirected to the event website after completing the survey.

## Real Data Used

Survey questions follow **PCMA (Professional Convention Management Association)** and **MPI (Meeting Professionals International)** post-event evaluation best practices, which are the industry-standard frameworks for measuring conference effectiveness. The conditional logic pattern (session feedback shown only to session attendees; improvement prompts shown only to dissatisfied attendees) is a textbook example from LimeSurvey's official Expression Manager documentation and professional survey design guides.

The survey covers:
- Overall conference experience (OVERALL_RATING numeric 1–10, RECOMMEND Y/N, IMPROVE_COMMENTS text)
- Session-specific feedback (ATTENDED_SESSIONS Y/N gate, SESSION_QUALITY array, BEST_SESSION text)
- Future event planning (RETURN_INTENT, FUTURE_TOPICS preferences)

## Verification Strategy

1. **Session Feedback group has a condition** (25 pts): `SELECT grelevance FROM lime_groups WHERE sid=X AND group_name LIKE '%Session%Feedback%'` — must be non-empty and not '1'
2. **Condition references ATTENDED_SESSIONS** (25 pts): Check that the `grelevance` expression contains a reference to ATTENDED_SESSIONS (e.g. `ATTENDED_SESSIONS.NAOK == 'Y'`)
3. **IMPROVE_COMMENTS condition references OVERALL_RATING** (25 pts): `SELECT relevance FROM lime_questions WHERE sid=X AND title='IMPROVE_COMMENTS'` — must reference OVERALL_RATING and a numeric threshold ≤ 6
4. **End URL set to techsummit domain** (25 pts): `SELECT surveyls_url FROM lime_surveys_languagesettings WHERE surveyls_survey_id=X AND surveyls_language='en'` — must contain 'techsummit'

Pass threshold: 70/100

## Schema Reference

```sql
-- Check group-level conditions (Expression Manager)
SELECT gid, group_name, grelevance
FROM lime_groups WHERE sid=X;

-- Via lime_group_l10ns if using LimeSurvey 6.x
SELECT g.gid, gl.group_name, g.grelevance
FROM lime_groups g
JOIN lime_group_l10ns gl ON g.gid=gl.gid
WHERE g.sid=X AND gl.language='en';

-- Check question-level conditions
SELECT qid, title, relevance
FROM lime_questions WHERE sid=X AND parent_qid=0;

-- Check end redirect URL
SELECT surveyls_url FROM lime_surveys_languagesettings
WHERE surveyls_survey_id=X AND surveyls_language='en';

-- Update group condition (Expression Manager syntax)
UPDATE lime_groups SET grelevance='ATTENDED_SESSIONS.NAOK == \"Y\"'
WHERE gid=<SESSION_GID>;

-- Update question condition
UPDATE lime_questions SET relevance='OVERALL_RATING.NAOK <= 6'
WHERE qid=<IMPROVE_QID>;

-- Update end URL
UPDATE lime_surveys_languagesettings
SET surveyls_url='http://techsummit.example.com/thank-you'
WHERE surveyls_survey_id=X AND surveyls_language='en';
```

## Expression Manager Syntax Reference

LimeSurvey's Expression Manager uses a custom expression language. Key patterns for this task:

```
# Show group only if ATTENDED_SESSIONS == 'Y'
ATTENDED_SESSIONS.NAOK == "Y"

# Show question only if OVERALL_RATING <= 6
OVERALL_RATING.NAOK <= 6

# Combined (AND logic)
ATTENDED_SESSIONS.NAOK == "Y" && SESSION_COUNT.NAOK > 0
```

The `.NAOK` suffix means "Not Applicable OK" — it returns the value without triggering a mandatory field error when the question is hidden. This is the standard way to safely reference earlier responses in LimeSurvey expressions.

## Edge Cases

- `grelevance` of `'1'` (the string literal "1") means "always show" — this is LimeSurvey's default and counts as NO condition
- The Expression Manager condition must use the question **code** (title field in lime_questions), not the question ID
- The `lime_group_l10ns` table holds the `group_name` in LimeSurvey 6.x; `lime_groups.grelevance` still holds the condition expression
- End URL is stored in `lime_surveys_languagesettings.surveyls_url` per language; set it for the 'en' language row
- The survey can be in either active or inactive state for conditions to be configured — activation is not required for this task
