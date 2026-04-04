#!/bin/bash
set -e

echo "=== Setting up Survey Flow Reorganization Task ==="

source /workspace/scripts/task_utils.sh

# Wait for LimeSurvey to be fully ready
wait_for_page_load 5

# Create the survey structure using Python and the JSON-RPC API
# We create it in the WRONG state:
# Order: Demographics (0), Shopping (1), Consent (2)
# Consent: Optional
# Income: Mandatory

echo "Creating survey with incorrect structure..."
python3 << 'PYEOF'
import json
import urllib.request
import sys
import time

URL = "http://localhost/index.php/admin/remotecontrol"
USER = "admin"
PASSWORD = "Admin123!"

def rpc(method, params, req_id=1):
    payload = {
        "method": method,
        "params": params,
        "id": req_id
    }
    req = urllib.request.Request(
        URL, 
        data=json.dumps(payload).encode(), 
        headers={"Content-Type": "application/json"}
    )
    try:
        response = urllib.request.urlopen(req)
        return json.loads(response.read())
    except Exception as e:
        print(f"Error calling {method}: {e}")
        return {"error": str(e), "result": None}

# 1. Get Session Key
key = rpc("get_session_key", [USER, PASSWORD]).get("result")
if not key:
    print("Failed to get session key")
    sys.exit(1)

# 2. Check for existing survey and delete if exists
surveys = rpc("list_surveys", [key]).get("result", [])
target_title = "Consumer Shopping Habits 2025"
for s in surveys:
    if s.get("surveyls_title") == target_title:
        print(f"Deleting existing survey {s['sid']}...")
        rpc("delete_survey", [key, s['sid']])

# 3. Create Survey
sid = rpc("add_survey", [key, 0, target_title, "en"]).get("result")
print(f"Created survey SID: {sid}")

# Save SID for bash script
with open("/tmp/task_survey_id", "w") as f:
    f.write(str(sid))

# 4. Create Groups in WRONG order
# We want Demographics first (wrong), Shopping middle, Consent last (wrong)
gid_demo = rpc("add_group", [key, sid, "Demographics", "Customer demographics"]).get("result")
gid_shop = rpc("add_group", [key, sid, "Shopping Habits", "General shopping behavior"]).get("result")
gid_consent = rpc("add_group", [key, sid, "Informed Consent", "Study agreement"]).get("result")

print(f"Created Groups: Demo={gid_demo}, Shop={gid_shop}, Consent={gid_consent}")

# 5. Add Questions with WRONG attributes

# Demographics: Income (Currently Mandatory - WRONG)
q_income = {
    "title": "DEMO_INC",
    "type": "N", # Numerical
    "mandatory": "Y", # WRONG (Should be N)
    "question": "What is your annual household income?"
}
rpc("add_question", [key, sid, gid_demo, "en", q_income])

# Shopping: Frequency (Neutral)
q_freq = {
    "title": "SHOP_FREQ",
    "type": "L", # List (Radio)
    "mandatory": "Y",
    "question": "How often do you shop online?"
}
rpc("add_question", [key, sid, gid_shop, "en", q_freq])

# Consent: Agreement (Currently Optional - WRONG)
q_consent = {
    "title": "CONSENT1",
    "type": "Y", # Yes/No
    "mandatory": "N", # WRONG (Should be Y)
    "question": "Do you agree to participate in this study?"
}
rpc("add_question", [key, sid, gid_consent, "en", q_consent])

rpc("release_session_key", [key])
print("Setup complete.")
PYEOF

SURVEY_ID=$(cat /tmp/task_survey_id)
echo "Survey ID stored: $SURVEY_ID"

# Record start time
date +%s > /tmp/task_start_time.txt

# Open Firefox to the Survey List
focus_firefox
DISPLAY=:1 xdotool key ctrl+l
sleep 0.5
DISPLAY=:1 xdotool type "http://localhost/index.php/admin/survey/sa/listSurveys"
DISPLAY=:1 xdotool key Return
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="