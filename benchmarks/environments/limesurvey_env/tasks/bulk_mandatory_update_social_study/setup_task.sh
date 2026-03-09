#!/bin/bash
set -e
echo "=== Setting up Bulk Mandatory Update task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for LimeSurvey to be responsive
wait_for_limesurvey() {
    for i in {1..30}; do
        if curl -s http://localhost/index.php/admin >/dev/null; then
            echo "LimeSurvey is responsive."
            return 0
        fi
        sleep 2
    done
    echo "Timeout waiting for LimeSurvey."
    return 1
}
wait_for_limesurvey

# Create the survey via Python API to ensure a clean, known state
echo "Creating initial survey data via API..."
python3 - << 'EOF'
import json
import urllib.request
import sys
import time

URL = "http://localhost/index.php/admin/remotecontrol"
USER = "admin"
PASS = "Admin123!"

def rpc(method, *params):
    payload = {
        "method": method,
        "params": params,
        "id": 1
    }
    data = json.dumps(payload).encode()
    req = urllib.request.Request(URL, data=data, headers={"Content-Type": "application/json"})
    try:
        response = urllib.request.urlopen(req)
        return json.loads(response.read())
    except Exception as e:
        return {"error": str(e)}

# Get Session Key
session = None
for _ in range(5):
    res = rpc("get_session_key", USER, PASS)
    if res and "result" in res and isinstance(res["result"], str):
        session = res["result"]
        break
    time.sleep(2)

if not session:
    print("Failed to get session key")
    sys.exit(1)

# Clean up if exists (delete by ID 12345)
rpc("delete_survey", session, 12345)

# 1. Create Survey
# add_survey(sSessionKey, iSurveyID, sSurveyTitle, sSurveyLanguage, sformat)
res = rpc("add_survey", session, 12345, "Community Cohesion Index 2025", "en", "G")
sid = 12345
print(f"Created survey {sid}")

# 2. Add Group
res = rpc("add_group", session, sid, "Neighborhood Dynamics")
gid = res.get("result")

if isinstance(gid, int):
    # 3. Add Questions
    # questions data: (Code, Text)
    questions = [
        ("Q1", "I feel like I belong to this community."),
        ("Q2", "People in this neighborhood can be trusted."),
        ("Q3", "If I needed help, my neighbors would provide it."),
        ("Q4", "I participate in local community events."),
        ("Q5", "Diversity makes our community stronger."),
        ("Q6", "I feel safe walking alone at night."),
        ("Q7", "Local government cares about my opinion."),
        ("Q8", "I plan to live here for the next 5 years."),
        ("Q9", "My neighbors and I share similar values.")
    ]

    # Add Likert scale questions (Type 'L' - List (Radio))
    # All initially Mandatory='N'
    for code, text in questions:
        rpc("add_question", session, sid, gid, code, text, "", "N", "L", [])

    # Add Q10 (Type 'T' - Long Free Text)
    rpc("add_question", session, sid, gid, "Q10", "Please share any additional comments about your neighborhood.", "", "N", "T", [])

    print("Questions added.")
else:
    print("Failed to create group.")

rpc("release_session_key", session)
EOF

# Verify setup in DB
SURVEY_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_surveys WHERE sid=12345")
if [ "$SURVEY_COUNT" -eq "0" ]; then
    echo "ERROR: Survey setup failed."
    exit 1
fi

# Record initial question state for integrity check (should be 10 questions)
INITIAL_Q_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_questions WHERE sid=12345 AND parent_qid=0")
echo "$INITIAL_Q_COUNT" > /tmp/initial_question_count

# Launch Firefox
echo "Launching Firefox..."
if ! pgrep -f "firefox" > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox -profile /home/ga/.mozilla/firefox/default.profile 'http://localhost/index.php/admin' &"
    sleep 5
fi

# Ensure window is ready and maximized
focus_firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Wait for UI to settle
sleep 2

# Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="