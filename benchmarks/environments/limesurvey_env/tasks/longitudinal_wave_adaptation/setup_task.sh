#!/bin/bash
set -e
echo "=== Setting up Longitudinal Wave Adaptation Task ==="

source /workspace/scripts/task_utils.sh

# Ensure LimeSurvey is ready
wait_for_limesurvey() {
    for i in {1..30}; do
        if curl -s http://localhost/index.php/admin >/dev/null; then
            return 0
        fi
        sleep 2
    done
    return 1
}
wait_for_limesurvey

# Python script to setup Wave 1 Survey via API
# We use Python because it's cleaner for JSON-RPC than curl/jq in bash
python3 << 'PYEOF'
import json
import urllib.request
import sys
import time

API_URL = "http://localhost/index.php/admin/remotecontrol"
USER = "admin"
PASS = "Admin123!"

def rpc(method, params):
    payload = {
        "method": method,
        "params": params,
        "id": 1
    }
    req = urllib.request.Request(
        API_URL, 
        data=json.dumps(payload).encode(),
        headers={'content-type': 'application/json'}
    )
    try:
        response = urllib.request.urlopen(req)
        return json.loads(response.read())
    except Exception as e:
        return {"error": str(e)}

# 1. Get Session Key
key = None
for i in range(10):
    res = rpc("get_session_key", [USER, PASS])
    if isinstance(res.get("result"), str):
        key = res["result"]
        break
    time.sleep(2)

if not key:
    print("Failed to get session key")
    sys.exit(1)

# 2. Cleanup: Delete any existing surveys with similar names to ensure clean state
surveys = rpc("list_surveys", [key, USER])
if isinstance(surveys.get("result"), list):
    for s in surveys["result"]:
        title = s.get("surveyls_title", "")
        if "Youth Development Study" in title:
            rpc("delete_survey", [key, s["sid"]])
            print(f"Deleted existing survey: {title}")

# 3. Create Wave 1 Survey
s_id = rpc("add_survey", [key, 0, "Youth Development Study - Wave 1", "en"])["result"]
print(f"Created Wave 1 Survey ID: {s_id}")

# 4. Add Groups
# G1: Baseline Demographics
g1_id = rpc("add_group", [key, s_id, "Baseline Demographics"])["result"]
# G2: School Experience
g2_id = rpc("add_group", [key, s_id, "School Experience"])["result"]
# G3: Family Context
g3_id = rpc("add_group", [key, s_id, "Family Context"])["result"]

# 5. Add Questions to Wave 1
# Demographics: Sex (L), DOB (D)
rpc("add_question", [key, s_id, g1_id, "sex", {"title": "sex", "type": "L", "question": "What is your sex?", "mandatory": "Y"}])
rpc("add_question", [key, s_id, g1_id, "dob", {"title": "dob", "type": "D", "question": "Date of Birth", "mandatory": "Y"}])

# School: GPA (N), Belonging (5)
rpc("add_question", [key, s_id, g2_id, "gpa", {"title": "gpa", "type": "N", "question": "What is your approximate GPA?", "mandatory": "N"}])
rpc("add_question", [key, s_id, g2_id, "belong", {"title": "belong", "type": "5", "question": "I feel like I belong at my school", "mandatory": "Y"}])

# Family: Living (L)
rpc("add_question", [key, s_id, g3_id, "living", {"title": "living", "type": "L", "question": "Who do you live with?", "mandatory": "Y"}])

# 6. Activate Wave 1 (so it looks 'real' and 'in progress')
rpc("activate_survey", [key, s_id])

rpc("release_session_key", [key])
PYEOF

# Record Start Time
date +%s > /tmp/task_start_time.txt

# Launch Firefox and login
focus_firefox
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
    sleep 5
fi

# Ensure window focus
DISPLAY=:1 wmctrl -a Firefox 2>/dev/null || true
sleep 2

# Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="