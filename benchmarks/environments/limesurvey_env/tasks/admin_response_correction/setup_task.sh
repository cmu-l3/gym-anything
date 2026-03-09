#!/bin/bash
set -e
echo "=== Setting up Task: Admin Response Correction ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for LimeSurvey API readiness
wait_for_limesurvey_api

# Use Python to interact with LimeSurvey API for robust setup
# We create a survey with an Email question to identify the user, 
# a Satisfaction question (Radio), and a Comments question (Text).
python3 -c '
import json
import urllib.request
import sys
import time

URL = "http://localhost/index.php/admin/remotecontrol"
USER = "admin"
PASS = "Admin123!"

def rpc(method, params, req_id=1):
    payload = {
        "method": method,
        "params": params,
        "id": req_id
    }
    data = json.dumps(payload).encode()
    req = urllib.request.Request(URL, data=data, headers={"Content-Type": "application/json"})
    try:
        response = urllib.request.urlopen(req)
        return json.loads(response.read())
    except Exception as e:
        print(f"RPC Error {method}: {e}")
        return None

# Get Session Key
res = rpc("get_session_key", [USER, PASS])
key = res["result"] if res else None

if not key or "error" in str(key):
    print("Failed to get session key")
    sys.exit(1)

# 1. Create Survey
print("Creating survey...")
res = rpc("add_survey", [key, 0, "IT Service Desk Satisfaction 2025", "en", "G"])
sid = res["result"]
print(f"Survey ID: {sid}")

# 2. Add Group
print("Adding group...")
res = rpc("add_group", [key, sid, "Feedback Section"])
gid = res["result"]
print(f"Group ID: {gid}")

# 3. Add Questions

# Q1: Email (Short Text) - used to identify the user
print("Adding Q1 (Email)...")
res = rpc("add_question", [key, sid, gid, "S", "QEMAIL", "Your Email Address", "Y"])
qid_email = res["result"]

# Q2: Satisfaction (List Radio)
print("Adding Q2 (Satisfaction)...")
# Note: creating question first, answers added later via DB for speed/reliability in setup
res = rpc("add_question", [key, sid, gid, "L", "QSAT", "How would you rate your overall experience?", "Y"])
qid_sat = res["result"]

# Q3: Comments (Long Text)
print("Adding Q3 (Comments)...")
res = rpc("add_question", [key, sid, gid, "T", "QCOM", "Additional Comments", "N"])
qid_com = res["result"]

# 4. Activate Survey
print("Activating survey...")
rpc("activate_survey", [key, sid])

# 5. Add Answer Options for Satisfaction (Direct DB injection to ensure correct codes)
# We use the qid_sat obtained above.
import subprocess
def run_db_query(query):
    cmd = ["limesurvey-db-query", query]
    subprocess.run(cmd)

# Insert answers 1-5
values = [
    ("1", "1 - Very Dissatisfied"),
    ("2", "2 - Dissatisfied"),
    ("3", "3 - Neutral"),
    ("4", "4 - Satisfied"),
    ("5", "5 - Very Satisfied")
]

for code, text in values:
    sql = f"INSERT INTO lime_answers (qid, code, answer, sortorder, language, scale_id) VALUES ({qid_sat}, \"{code}\", \"{text}\", {code}, \"en\", 0);"
    run_db_query(sql)

# 6. Inject the "Wrong" Response
# API add_response requires question codes as keys.
response_data = {
    "QEMAIL": "michael.chang@acmecorp.com",
    "QSAT": "1",                    # The mistake (1 instead of 5)
    "QCOM": "Service was quick, but I clicked the wrong button maybe?",
    "submitdate": "2023-10-27 10:00:00",
    "lastpage": 1
}
print("Injecting initial response...")
res = rpc("add_response", [key, sid, response_data])
print(f"Response ID: {res['result']}")

rpc("release_session_key", [key])
'

# Capture initial state of the specific response for verification comparison
# We need to find the response ID for Michael Chang
SID=$(limesurvey_query "SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE surveyls_title = 'IT Service Desk Satisfaction 2025' LIMIT 1")
# Determine column names (format usually {SID}X{GID}X{QID})
# But we can select * and filter.
# Better: Get the exact ID.
RESP_ID=$(limesurvey_query "SELECT id FROM lime_survey_$SID WHERE \`$SIDX${GID}X${QEMAIL}\` LIKE '%michael.chang%' LIMIT 1" 2>/dev/null || echo "")

# If we can't easily predict column names in bash, we'll just record the row count
INITIAL_COUNT=$(get_response_count "$SID")
echo "$INITIAL_COUNT" > /tmp/initial_response_count
echo "$SID" > /tmp/task_survey_sid

# Ensure Firefox is running
if ! pgrep -f "firefox" > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
fi

# Wait for window and maximize
wait_for_window "Firefox"
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="