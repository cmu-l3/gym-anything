#!/bin/bash
set -e

echo "=== Setting up completion_workflow_config task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Wait for LimeSurvey to be ready
echo "Checking LimeSurvey availability..."
wait_for_limesurvey() {
    for i in {1..30}; do
        if curl -s -o /dev/null -w "%{http_code}" http://localhost/index.php/admin | grep -q "200\|302"; then
            echo "LimeSurvey is ready."
            return 0
        fi
        sleep 2
    done
    echo "Timeout waiting for LimeSurvey."
    return 1
}
wait_for_limesurvey

# Create the survey via Python script interacting with DB
# We do this to ensure a consistent starting state with specific text but DEFAULT settings
echo "Creating TechSummit survey..."
python3 << 'PYEOF'
import subprocess
import time
import sys

def db_exec(sql):
    cmd = ["docker", "exec", "limesurvey-db", "mysql", "-u", "limesurvey", "-plimesurvey_pass", "limesurvey", "-e", sql]
    subprocess.run(cmd, check=True, capture_output=True)

def db_query_val(sql):
    cmd = ["docker", "exec", "limesurvey-db", "mysql", "-u", "limesurvey", "-plimesurvey_pass", "limesurvey", "-N", "-e", sql]
    res = subprocess.run(cmd, capture_output=True, text=True)
    return res.stdout.strip()

# 1. Cleanup existing survey if needed
existing_sid = db_query_val("SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE surveyls_title LIKE '%TechSummit%2024%' LIMIT 1")
if existing_sid:
    print(f"Removing existing survey {existing_sid}...")
    db_exec(f"DELETE FROM lime_surveys WHERE sid={existing_sid}")
    db_exec(f"DELETE FROM lime_surveys_languagesettings WHERE surveyls_survey_id={existing_sid}")
    db_exec(f"DELETE FROM lime_groups WHERE sid={existing_sid}")
    db_exec(f"DELETE FROM lime_questions WHERE sid={existing_sid}")

# 2. Create new survey (SID 884921)
# Important: Set operational settings to DEFAULTS (active=N, anonymized=N, format=G)
# autoredirect=N, allowsave=N, datestamp=N, emailnotificationto=''
sid = 884921
print(f"Creating survey {sid}...")

# Insert into lime_surveys
db_exec(f"""
INSERT INTO lime_surveys (sid, owner_id, active, format, language, datecreated, autoredirect, allowsave, datestamp, emailnotificationto)
VALUES ({sid}, 1, 'N', 'G', 'en', NOW(), 'N', 'N', 'N', '');
""")

# Insert into lime_surveys_languagesettings
# Set defaults for url/endtext
title = "TechSummit 2024 Post-Conference Evaluation"
desc = "Post-conference evaluation for TechSummit 2024 annual technology conference."
welcome = "Welcome to the TechSummit 2024 evaluation."
db_exec(f"""
INSERT INTO lime_surveys_languagesettings (surveyls_survey_id, surveyls_language, surveyls_title, surveyls_description, surveyls_welcometext, surveyls_endtext, surveyls_url, surveyls_urldescription)
VALUES ({sid}, 'en', '{title}', '{desc}', '{welcome}', '', '', '');
""")

# 3. Add Question Groups and Questions (for realism)
# Group 1
db_exec(f"INSERT INTO lime_groups (gid, sid, group_name, group_order) VALUES ({sid}01, {sid}, 'Session Quality', 0);")
# Q1 - Keynote Quality (List)
db_exec(f"INSERT INTO lime_questions (qid, parent_qid, sid, gid, type, title, question_order, mandatory) VALUES ({sid}011, 0, {sid}, {sid}01, 'L', 'Q1', 0, 'Y');")
db_exec(f"INSERT INTO lime_question_l10ns (qid, question, language) VALUES ({sid}011, 'How would you rate the keynote?', 'en');")

# Group 2
db_exec(f"INSERT INTO lime_groups (gid, sid, group_name, group_order) VALUES ({sid}02, {sid}, 'Overall Experience', 1);")
# Q2 - NPS (Numerical)
db_exec(f"INSERT INTO lime_questions (qid, parent_qid, sid, gid, type, title, question_order, mandatory) VALUES ({sid}021, 0, {sid}, {sid}02, 'N', 'Q2', 0, 'Y');")
db_exec(f"INSERT INTO lime_question_l10ns (qid, question, language) VALUES ({sid}021, 'How likely are you to recommend TechSummit?', 'en');")

print("Survey creation complete.")
PYEOF

# Record initial state for anti-gaming comparison
SURVEY_ID="884921"
echo "$SURVEY_ID" > /tmp/task_survey_id.txt

# Launch Firefox and navigate to survey admin page
echo "Launching Firefox..."
if pkill -f firefox; then sleep 2; fi

# We navigate directly to the specific survey's summary page to save agent time
# URL pattern: index.php/admin/survey/sa/view/surveyid/{SID}
START_URL="http://localhost/index.php/admin/survey/sa/view/surveyid/$SURVEY_ID"

su - ga -c "DISPLAY=:1 firefox -profile /home/ga/.mozilla/firefox/default.profile '$START_URL' &"

# Wait for window
for i in {1..20}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox"; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Initial screenshot
sleep 3
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="