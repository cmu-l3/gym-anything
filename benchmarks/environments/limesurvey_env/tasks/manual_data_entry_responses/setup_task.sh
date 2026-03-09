#!/bin/bash
set -e
echo "=== Setting up Manual Data Entry Task ==="

source /workspace/scripts/task_utils.sh

# 1. Record Start Time
date +%s > /tmp/task_start_time.txt

# 2. Wait for LimeSurvey API
wait_for_limesurvey_api() {
    local timeout=60
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if curl -s http://localhost/index.php/admin/remotecontrol >/dev/null; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    return 1
}
wait_for_limesurvey_api

# 3. Create and Activate Survey via Python API script
# This ensures the survey exists, has the right structure, and is active (creating the response table)
cat > /tmp/create_survey.py << 'EOF'
import json
import urllib.request
import sys
import time

URL = "http://localhost/index.php/admin/remotecontrol"
USER = "admin"
PASS = "Admin123!"

def rpc(method, params):
    payload = {
        "method": method,
        "params": params,
        "id": 1
    }
    req = urllib.request.Request(
        URL, 
        data=json.dumps(payload).encode(),
        headers={'content-type': 'application/json'}
    )
    try:
        response = urllib.request.urlopen(req)
        return json.loads(response.read())
    except Exception as e:
        print(f"RPC Error: {e}")
        return {"result": None, "error": str(e)}

# Get Session Key
key = rpc("get_session_key", [USER, PASS]).get("result")
if not key:
    print("Failed to get session key")
    sys.exit(1)

# Cleanup old survey if exists
surveys = rpc("list_surveys", [key]).get("result", [])
target_title = "Community Health Needs Assessment 2024"
if isinstance(surveys, list):
    for s in surveys:
        if s.get("surveyls_title") == target_title:
            rpc("delete_survey", [key, s.get("sid")])
            print(f"Deleted old survey: {s.get("sid")}")

# Create Survey
sid = rpc("add_survey", [key, 0, target_title, "en"]).get("result")
print(f"Created survey: {sid}")

# Create Group
gid = rpc("add_group", [key, sid, "Health Status and Access"]).get("result")

# Question 1: ZIP (Short Text)
q1 = rpc("add_question", [key, sid, gid, "en", {"title": "QZIP", "type": "S", "question": "What is your 5-digit ZIP code?", "question_order": 1}]).get("result")

# Question 2: Health (List Radio)
q2 = rpc("add_question", [key, sid, gid, "en", {"title": "QHEALTH", "type": "L", "question": "Would you say that in general your health is:", "question_order": 2}]).get("result")
# Answers for Q2
answers_health = [
    ("EX", "Excellent"),
    ("VG", "Very good"),
    ("GD", "Good"),
    ("FR", "Fair"),
    ("PR", "Poor")
]
for code, answer in answers_health:
    rpc("add_answer", [key, sid, q2, {"code": code, "answer": answer, "language": "en"}])

# Question 3: Physical Health Days (Numerical)
q3 = rpc("add_question", [key, sid, gid, "en", {"title": "QDAYS", "type": "N", "question": "During the past 30 days, for about how many days was your physical health not good?", "question_order": 3}]).get("result")

# Question 4: Insured (List Radio)
q4 = rpc("add_question", [key, sid, gid, "en", {"title": "QINSURED", "type": "L", "question": "Do you have any kind of health care coverage?", "question_order": 4}]).get("result")
# Answers for Q4
answers_insured = [
    ("Y", "Yes"),
    ("N", "No"),
    ("DK", "Don't know")
]
for code, answer in answers_insured:
    rpc("add_answer", [key, sid, q4, {"code": code, "answer": answer, "language": "en"}])

# Question 5: Age (Numerical)
q5 = rpc("add_question", [key, sid, gid, "en", {"title": "QAGE", "type": "N", "question": "What is your age in years?", "question_order": 5}]).get("result")

# Activate Survey
status = rpc("activate_survey", [key, sid]).get("result")
print(f"Activation status: {status}")

# Release key
rpc("release_session_key", [key])

# Save SID for other scripts
with open("/tmp/task_sid.txt", "w") as f:
    f.write(str(sid))
EOF

python3 /tmp/create_survey.py

# 4. Prepare Browser
# Focus Firefox
focus_firefox

# Navigate to Survey List
DISPLAY=:1 xdotool key ctrl+l
sleep 0.5
DISPLAY=:1 xdotool type "http://localhost/index.php/admin/survey/sa/listsurveys"
DISPLAY=:1 xdotool key Return
sleep 5

# 5. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="