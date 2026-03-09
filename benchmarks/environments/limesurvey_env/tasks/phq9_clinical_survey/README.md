# Task: PHQ-9 Clinical Survey Construction

## Domain Context

Social science research assistants and clinical psychology researchers routinely deploy validated psychometric instruments as online surveys for data collection in mental health studies. The PHQ-9 (Patient Health Questionnaire-9) is a validated, public-domain depression screening tool (Kroenke, Spitzer & Williams, 2001) used in thousands of research studies worldwide. Properly configuring it in a survey platform — with correct question types, anonymization, and IRB-compliant settings — is a core competency for health researchers using LimeSurvey.

## Occupation Context (from master_dataset.csv)
- **Social Science Research Assistants** (SOC 19-4061): "Designing and administering data collection instruments for primary research"
- **Survey Researchers** (SOC 19-3022): "Designing questionnaires, programming logic/skip patterns, and managing sampling frames"
- **Psychology Teachers, Postsecondary** (SOC 25-1066): "Widely used for data collection in social and personality psychology research"

## Task Goal

Build a complete, IRB-compliant PHQ-9 survey in LimeSurvey from scratch:
- Create survey titled 'PHQ-9 Mental Health Screening Study 2024'
- 3 question groups: Symptom Frequency, Functional Impact, Demographics
- PHQ-9 Array question with 9 sub-questions and 4 response options
- Mandatory PHQ-9 question, anonymized responses, survey activated

## Real Data Used

The PHQ-9 questions are a **public domain** validated clinical instrument (Pfizer Inc., no copyright). The 9 items:
1. Little interest or pleasure in doing things
2. Feeling down, depressed, or hopeless
3. Trouble falling or staying asleep, or sleeping too much
4. Feeling tired or having little energy
5. Poor appetite or overeating
6. Feeling bad about yourself — or that you are a failure
7. Trouble concentrating on things
8. Moving or speaking slowly or being fidgety/restless
9. Thoughts that you would be better off dead or of hurting yourself

Response scale: Not at all (0) / Several days (1) / More than half the days (2) / Nearly every day (3)

## Verification Strategy

All verification is done via MySQL queries on the LimeSurvey database:

1. **Survey exists** (gate): `lime_surveys` + `lime_surveys_languagesettings` — check title contains 'PHQ' or 'mental health screening'
2. **3 question groups** (25 pts): `SELECT COUNT(*) FROM lime_groups WHERE sid=X`
3. **Array question with ≥ 9 sub-questions** (25 pts): `lime_questions` type IN ('F','H','1','A','B','C','E') + sub-question count via `parent_qid`
4. **Anonymized = Y** (25 pts): `SELECT anonymized FROM lime_surveys WHERE sid=X`
5. **Active = Y** (25 pts): `SELECT active FROM lime_surveys WHERE sid=X`

Pass threshold: 70/100

## Schema Reference

```sql
-- Check survey settings
SELECT sid, active, anonymized FROM lime_surveys WHERE sid=X;

-- Check groups
SELECT gid, group_name FROM lime_groups WHERE sid=X;

-- Check questions and types
SELECT qid, type, mandatory FROM lime_questions WHERE sid=X AND parent_qid=0;

-- Check sub-questions (PHQ-9 items)
SELECT COUNT(*) FROM lime_questions WHERE parent_qid=<array_qid>;

-- Check answer options
SELECT code, answer FROM lime_answers a
JOIN lime_answer_l10ns al ON a.qid=al.qid WHERE a.qid=<array_qid>;
```

## Edge Cases
- Agent may use Array (5 pt) type 'F' or Flexible Array '1' — both count
- Array sub-questions stored with parent_qid pointing to the parent array question
- Survey activation changes `active` field from 'N' to 'Y' in lime_surveys
- Anonymization is a separate toggle in survey settings, stored in `anonymized` column
