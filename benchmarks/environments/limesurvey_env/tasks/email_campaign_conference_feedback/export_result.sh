#!/bin/bash
echo "=== Exporting Email Campaign Results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

SID=$(cat /tmp/task_survey_id 2>/dev/null)
if [ -z "$SID" ]; then
    # Fallback search if ID file missing
    SID=$(limesurvey_query "SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE surveyls_title LIKE '%2024 SIOP%' LIMIT 1")
fi

if [ -z "$SID" ]; then
    echo "ERROR: Survey not found."
    # Create empty result file
    echo '{"found": false}' > /tmp/task_result.json
    exit 0
fi

# Query Email Templates
# We use Python to handle JSON serialization properly to avoid issue with newlines/quotes in SQL output
python3 - << PYEOF
import json
import subprocess

def query_db(sql):
    cmd = ["docker", "exec", "limesurvey-db", "mysql", "-u", "limesurvey", "-plimesurvey_pass", "limesurvey", "-N", "-e", sql]
    try:
        res = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode('utf-8').strip()
        return res
    except:
        return ""

sid = "$SID"

# Fetch Template Data
invite_subj = query_db(f"SELECT surveyls_email_invite_subj FROM lime_surveys_languagesettings WHERE surveyls_survey_id={sid}")
invite_body = query_db(f"SELECT surveyls_email_invite FROM lime_surveys_languagesettings WHERE surveyls_survey_id={sid}")

remind_subj = query_db(f"SELECT surveyls_email_remind_subj FROM lime_surveys_languagesettings WHERE surveyls_survey_id={sid}")
remind_body = query_db(f"SELECT surveyls_email_remind FROM lime_surveys_languagesettings WHERE surveyls_survey_id={sid}")

confirm_subj = query_db(f"SELECT surveyls_email_confirm_subj FROM lime_surveys_languagesettings WHERE surveyls_survey_id={sid}")
confirm_body = query_db(f"SELECT surveyls_email_confirm FROM lime_surveys_languagesettings WHERE surveyls_survey_id={sid}")

# Fetch General Settings
admin_email = query_db(f"SELECT adminemail FROM lime_surveys WHERE sid={sid}")
bounce_email = query_db(f"SELECT bounce_email FROM lime_surveys WHERE sid={sid}")

# Create Result Dictionary
result = {
    "found": True,
    "sid": sid,
    "invite": {
        "subject": invite_subj,
        "body": invite_body
    },
    "reminder": {
        "subject": remind_subj,
        "body": remind_body
    },
    "confirmation": {
        "subject": confirm_subj,
        "body": confirm_body
    },
    "settings": {
        "admin_email": admin_email,
        "bounce_email": bounce_email
    },
    "timestamp": subprocess.check_output(["date", "+%s"]).decode().strip()
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=4)

print("Exported JSON result.")
PYEOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="