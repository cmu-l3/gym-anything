#!/bin/bash
set -e

echo "=== Exporting completion_workflow_config results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Get Survey ID
SURVEY_ID=$(cat /tmp/task_survey_id.txt 2>/dev/null || echo "884921")

# Python script to fetch database state and export to JSON
python3 << PYEOF
import subprocess
import json
import time

sid = "$SURVEY_ID"
task_start = int("$TASK_START")
task_end = int("$TASK_END")

def db_query(sql):
    cmd = ["docker", "exec", "limesurvey-db", "mysql", "-u", "limesurvey", "-plimesurvey_pass", "limesurvey", "-N", "-e", sql]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True)
        return res.stdout.strip()
    except Exception:
        return ""

# Fetch Operational Settings (lime_surveys)
# autoredirect, allowsave, datestamp, emailnotificationto, active
ops_sql = f"SELECT autoredirect, allowsave, datestamp, emailnotificationto, active FROM lime_surveys WHERE sid={sid}"
ops_res = db_query(ops_sql).split('\t')
if len(ops_res) < 5:
    ops_data = {"autoredirect": "N", "allowsave": "N", "datestamp": "N", "email": "", "active": "N"}
else:
    ops_data = {
        "autoredirect": ops_res[0],
        "allowsave": ops_res[1],
        "datestamp": ops_res[2],
        "email": ops_res[3],
        "active": ops_res[4]
    }

# Fetch Text Settings (lime_surveys_languagesettings)
# surveyls_endtext, surveyls_url, surveyls_urldescription
text_sql = f"SELECT surveyls_endtext, surveyls_url, surveyls_urldescription FROM lime_surveys_languagesettings WHERE surveyls_survey_id={sid} AND surveyls_language='en'"
text_res = db_query(text_sql).split('\t')

# Handle potentially empty text fields or multiline text issues by simpler fetch if needed
# But for now assuming basic tab separation works. If endtext contains tabs/newlines, mysql -N might need help.
# Let's try a safer retrieval for endtext if it might contain complex chars.
# We'll trust the basic retrieval for this specific task logic or fallback to defaults.
if len(text_res) < 3:
    # It's possible text contains newlines, confusing the split. Let's fetch individually.
    endtext = db_query(f"SELECT surveyls_endtext FROM lime_surveys_languagesettings WHERE surveyls_survey_id={sid} AND surveyls_language='en'")
    url = db_query(f"SELECT surveyls_url FROM lime_surveys_languagesettings WHERE surveyls_survey_id={sid} AND surveyls_language='en'")
    desc = db_query(f"SELECT surveyls_urldescription FROM lime_surveys_languagesettings WHERE surveyls_survey_id={sid} AND surveyls_language='en'")
else:
    endtext = text_res[0]
    url = text_res[1]
    desc = text_res[2]

result = {
    "task_start": task_start,
    "task_end": task_end,
    "survey_id": sid,
    "settings": {
        "autoredirect": ops_data["autoredirect"],
        "allowsave": ops_data["allowsave"],
        "datestamp": ops_data["datestamp"],
        "emailnotificationto": ops_data["email"],
        "active": ops_data["active"],
        "surveyls_endtext": endtext,
        "surveyls_url": url,
        "surveyls_urldescription": desc
    }
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Exported result to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="