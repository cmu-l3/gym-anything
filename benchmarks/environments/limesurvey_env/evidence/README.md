# LimeSurvey Environment Evidence Documentation

This document captures the evidence from interactive testing of the LimeSurvey environment tasks using ask_cua.py.

## Environment Details

- **Environment ID**: limesurvey_env@0.1
- **Base**: ubuntu-gnome-systemd_highres (QEMU VM)
- **SSH Port**: 2398 (dynamically assigned)
- **Test Date**: 2026-02-03

## LimeSurvey Credentials

- **Admin User**: admin
- **Admin Password**: Admin123!
- **URL**: http://localhost/index.php/admin

## Tasks Tested

### 1. create_survey
**Objective**: Create a new survey titled "Customer Satisfaction Survey"

**Steps Performed**:
1. Login to LimeSurvey admin panel
2. Click "Create a new survey" from welcome dialog
3. Enter survey title "Customer Satisfaction Survey"
4. Click "Create survey" button

**Result**: SUCCESS
- Survey ID: 378298
- Survey created with auto-generated question group

**Screenshots**:
- 01_login_page.png - LimeSurvey login page
- 02_welcome_dialog.png - Welcome dialog with create survey option
- 03_create_survey_form.png - Survey creation form
- 04_survey_created.png - Survey created successfully

### 2. add_question
**Objective**: Add a numerical input question "What is your age?" with code QAGE

**Steps Performed**:
1. Navigate to survey structure
2. Click "Add question"
3. Enter code "QAGE" in the General settings
4. Enter question text "What is your age?"
5. Select question type "Numerical input" from Mask questions
6. Click "Save"

**Result**: SUCCESS
- Question ID: 4
- Question Code: QAGE
- Question Type: N (Numerical)
- Question Text: "What is your age?"

**Screenshots**:
- 05_add_question_form.png - Question creation form with text entered
- 06_question_saved.png - Question saved confirmation

### 3. submit_response
**Objective**: Submit a survey response with age=35

**Steps Performed**:
1. Activate the survey (open access mode)
2. Navigate to survey public URL
3. Click "Next" to start survey
4. Enter "35" in the age field
5. Click "Submit"

**Result**: SUCCESS
- Response ID: 1
- Submit Date: 2026-02-03 18:02:41
- Age Value: 35.0000000000

**Screenshots**:
- 07_survey_activated.png - Survey activation success
- 08_survey_form.png - Survey questions displayed
- 09_survey_filled.png - Age value 35 entered
- 10_survey_submitted.png - Thank you confirmation page

## Database Verification

### Survey Created
```sql
SELECT surveyls_survey_id, surveyls_title FROM lime_surveys_languagesettings;
-- Result: 378298 | Customer Satisfaction Survey
```

### Question Added
```sql
SELECT q.qid, q.title, q.type, ql.question
FROM lime_questions q
LEFT JOIN lime_question_l10ns ql ON q.qid=ql.qid
WHERE q.sid=378298 AND q.parent_qid=0;
-- Result: 4 | QAGE | N | What is your age?
```

### Response Submitted
```sql
SELECT * FROM lime_survey_378298;
-- Response with id=1, age value=35.0000000000
```

## Technical Notes

### Coordinate Scaling
CUA returns coordinates normalized to 1280x720. Scale to actual resolution:
```python
actual_x = int(cua_x * 1920 / 1280)
actual_y = int(cua_y * 1080 / 720)
```

### LimeSurvey Database Schema
- `lime_surveys` - Survey metadata
- `lime_surveys_languagesettings` - Survey titles (surveyls_survey_id, surveyls_title)
- `lime_questions` - Question definitions (qid, sid, title, type)
- `lime_question_l10ns` - Question text (qid, question)
- `lime_survey_XXXX` - Response data per survey

### Known Issues Fixed
1. Column name `sid` vs `surveyls_survey_id` in language settings table
2. Question text stored in `lime_question_l10ns` not `lime_questions`
3. Code field doesn't allow underscores (Q_AGE -> QAGE)
