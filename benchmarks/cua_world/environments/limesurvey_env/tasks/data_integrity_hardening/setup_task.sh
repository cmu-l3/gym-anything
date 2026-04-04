#!/bin/bash
set -e
echo "=== Setting up Data Integrity Hardening Task ==="

source /workspace/scripts/task_utils.sh

# Define database query helper if not present
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

# Wait for LimeSurvey API availability
echo "Waiting for LimeSurvey API..."
python3 << 'PYEOF'
import json, urllib.request, sys, time

BASE = "http://localhost/index.php/admin/remotecontrol"

def api(method, params):
    data = json.dumps({"method": method, "params": params, "id": 1}).encode()
    req = urllib.request.Request(BASE, data=data, headers={"Content-Type": "application/json"})
    try:
        return json.loads(urllib.request.urlopen(req, timeout=10).read())
    except Exception as e:
        return {"result": None, "error": str(e)}

# Wait loop
for i in range(20):
    try:
        resp = api("get_session_key", ["admin", "Admin123!"])
        if resp.get("result") and "error" not in str(resp.get("result")):
            print("API Ready")
            sys.exit(0)
    except:
        pass
    time.sleep(3)
sys.exit(1)
PYEOF

# Create the survey structure using Python script
echo "Creating survey structure..."
python3 << 'PYEOF'
import json, urllib.request, sys

BASE = "http://localhost/index.php/admin/remotecontrol"

def api(method, params):
    data = json.dumps({"method": method, "params": params, "id": 1}).encode()
    req = urllib.request.Request(BASE, data=data, headers={"Content-Type": "application/json"})
    return json.loads(urllib.request.urlopen(req).read())

# Get session
session = api("get_session_key", ["admin", "Admin123!"])["result"]

# 1. Create Survey
title = "Hypertension Study - Subject Screening (Protocol H-2024)"
# Check if exists and delete
surveys = api("list_surveys", [session]).get("result", [])
if isinstance(surveys, list):
    for s in surveys:
        if s.get("surveyls_title") == title:
            api("delete_survey", [session, s["sid"]])

sid = api("add_survey", [session, 0, title, "en"])["result"]
print(f"Created Survey SID: {sid}")

# 2. Create Group
gid = api("add_group", [session, sid, "Screening Data", "Primary subject data"])["result"]

# 3. Create Questions (No validation initially)

# SUBJID - Short Text
q1 = {
    "title": "SUBJID",
    "type": "S", # Short text
    "mandatory": "Y",
    "question_order": 1
}
q1_l10n = {"en": {"question": "Subject ID", "help": "Enter the 6-character subject code"}}
qid1 = api("add_question", [session, sid, gid, "en", q1, q1_l10n])["result"]

# BP_SYS - Numerical
q2 = {
    "title": "BP_SYS",
    "type": "N", # Numerical
    "mandatory": "Y",
    "question_order": 2
}
q2_l10n = {"en": {"question": "Systolic Blood Pressure (mmHg)"}}
qid2 = api("add_question", [session, sid, gid, "en", q2, q2_l10n])["result"]

# BP_DIA - Numerical
q3 = {
    "title": "BP_DIA",
    "type": "N", # Numerical
    "mandatory": "Y",
    "question_order": 3
}
q3_l10n = {"en": {"question": "Diastolic Blood Pressure (mmHg)"}}
qid3 = api("add_question", [session, sid, gid, "en", q3, q3_l10n])["result"]

# SCREEN_DATE - Date/Time
q4 = {
    "title": "SCREEN_DATE",
    "type": "D", # Date
    "mandatory": "Y",
    "question_order": 4
}
q4_l10n = {"en": {"question": "Date of Screening"}}
qid4 = api("add_question", [session, sid, gid, "en", q4, q4_l10n])["result"]

print("Survey structure created.")
api("release_session_key", [session])
PYEOF

# Record start time
date +%s > /tmp/task_start_time.txt

# Launch Firefox
echo "Launching Firefox..."
focus_firefox 2>/dev/null || true
if ! pgrep -f "firefox" > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
else
    # Navigate if already open
    DISPLAY=:1 xdotool search --onlyvisible --class "firefox" windowactivate key --window 0 ctrl+l type "http://localhost/index.php/admin" key Return
fi

# Wait for window and maximize
sleep 5
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
    DISPLAY=:1 wmctrl -i -a "$WID"
fi

# Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="