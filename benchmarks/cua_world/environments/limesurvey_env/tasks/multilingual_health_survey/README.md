# Task: Multilingual Vaccine Hesitancy Survey — Spanish Translation

## Domain Context

Public health researchers conducting community health studies in bilingual populations must provide surveys in multiple languages to reach all community members. Survey researchers and social science research assistants who use LimeSurvey need to add language translations to existing surveys — a professional workflow that involves not just adding a language code but translating all question text, answer options, group names, survey title, and description. This reflects real practice in epidemiological research targeting Hispanic/Latino communities in the United States.

## Occupation Context (from master_dataset.csv)
- **Survey Researchers** (SOC 19-3022): "Designing questionnaires, programming logic/skip patterns" — multilingual surveys are standard practice
- **Social Science Research Assistants** (SOC 19-4061): "Designing and administering data collection instruments for primary research" — bilingual instruments are common in community health research

## Task Goal

Add Spanish (es) as a second language to the pre-built English "Vaccine Acceptance and Hesitancy Study":
1. Add Spanish language to survey settings
2. Provide Spanish survey title (should include "vacun" or related terms)
3. Translate all 8 survey questions into Spanish
4. Translate answer options for the 3 multiple-choice questions
5. (Bonus) Translate question group names

## Real Data Used

Survey questions based on the **WHO SAGE Working Group on Vaccine Hesitancy** determinants framework (Larson et al., 2014, Vaccine). This framework is the standard international reference for measuring vaccine hesitancy and is used in hundreds of peer-reviewed epidemiological studies.

The 8 questions cover: vaccination status, vaccine types received, access ease, side effects, perceived importance, safety confidence, effectiveness confidence, and hesitancy reasons.

## Verification Strategy

1. **Spanish language added** (25 pts): `SELECT COUNT(*) FROM lime_surveys_languagesettings WHERE surveyls_survey_id=X AND surveyls_language='es'`
2. **Spanish title with keyword** (25 pts): `SELECT surveyls_title FROM lime_surveys_languagesettings WHERE language='es'` — check for 'vacun*' or 'encuesta' or 'salud'
3. **Question translations** (30 pts): `SELECT COUNT(DISTINCT ql.qid) FROM lime_question_l10ns ql JOIN lime_questions q ON ql.qid=q.qid WHERE q.sid=X AND q.parent_qid=0 AND ql.language='es'` — need >= 6
4. **Answer translations** (20 pts): `SELECT COUNT(DISTINCT al.aid) FROM lime_answer_l10ns al JOIN lime_answers a ON al.aid=a.id JOIN lime_questions q ON a.qid=q.qid WHERE q.sid=X AND al.language='es'` — need >= 10

Pass threshold: 70/100

## Schema Reference

```sql
-- Survey languages
SELECT surveyls_language, surveyls_title FROM lime_surveys_languagesettings WHERE surveyls_survey_id=X;

-- Question translations by language
SELECT q.title, ql.language, ql.question FROM lime_questions q
JOIN lime_question_l10ns ql ON q.qid=ql.qid
WHERE q.sid=X AND q.parent_qid=0;

-- Answer translations
SELECT a.code, al.language, al.answer FROM lime_answers a
JOIN lime_answer_l10ns al ON a.id=al.aid
JOIN lime_questions q ON a.qid=q.qid
WHERE q.sid=X;
```
