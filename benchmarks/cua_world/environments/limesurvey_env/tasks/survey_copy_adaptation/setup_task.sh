#!/bin/bash
set -e
echo "=== Setting up Survey Copy Adaptation Task ==="

source /workspace/scripts/task_utils.sh

# Ensure LimeSurvey is ready
wait_for_page_load 5

# Create the source survey "Annual Tech Conference 2024 Feedback" using Python API
# This ensures a clean, consistent starting state
echo "Creating source survey..."
python3 << 'PYEOF'
import json, urllib.request, sys, time

BASE = "http://localhost/index.php/admin/remotecontrol"

def api(method, params):
    payload = {
        "method": method,
        "params": params,
        "id": 1
    }
    req = urllib.request.Request(BASE, data=json.dumps(payload).encode(), headers={"Content-Type": "application/json"})
    try:
        response = urllib.request.urlopen(req, timeout=10)
        return json.loads(response.read())
    except Exception as e:
        return {"error": str(e)}

# Get Session Key
session_key = None
for i in range(10):
    res = api("get_session_key", ["admin", "Admin123!"])
    if isinstance(res.get("result"), str):
        session_key = res["result"]
        break
    time.sleep(2)

if not session_key:
    print("Failed to get session key")
    sys.exit(1)

# Check if source survey already exists and delete it to be safe
surveys = api("list_surveys", [session_key]).get("result", [])
if isinstance(surveys, list):
    for s in surveys:
        if "Annual Tech Conference" in s.get("surveyls_title", ""):
            print(f"Deleting existing survey {s['sid']}")
            api("delete_survey", [session_key, s['sid']])

# Create Source Survey
sid = api("add_survey", [session_key, 0, "Annual Tech Conference 2024 Feedback", "en"])["result"]
print(f"Created survey SID: {sid}")

# Set description and welcome text for source
props = {
    "description": "Feedback for the annual tech gathering.",
    "welcometext": "Welcome to the 2024 Tech Conference feedback form."
}
api("set_language_properties", [session_key, sid, props, "en"])

# Add Groups
g1 = api("add_group", [session_key, sid, "Keynote Sessions", "Feedback on main stage speakers"])["result"]
g2 = api("add_group", [session_key, sid, "Breakout Tracks", "Technical deep dives"])["result"]
g3 = api("add_group", [session_key, sid, "Logistics & Venue", "Food, wifi, and location"])["result"]

# Add some questions to make it realistic
# Q1 in G1
q1_data = {"title": "KeynoteSat", "type": "5", "mandatory": "Y", "question": "Rate the opening keynote:"}
api("add_question", [session_key, sid, g1, "en", q1_data])

# Q2 in G2
q2_data = {"title": "NPS", "type": "N", "mandatory": "N", "question": "How likely are you to recommend this conference?"}
api("add_question", [session_key, sid, g2, "en", q2_data])

print(f"Source survey setup complete. SID: {sid}")
with open("/tmp/source_sid.txt", "w") as f:
    f.write(str(sid))
PYEOF

SOURCE_SID=$(cat /tmp/source_sid.txt 2>/dev/null)
echo "Source Survey ID: $SOURCE_SID"

# Record start time
date +%s > /tmp/task_start_time.txt

# Open Firefox to Admin Login
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
    sleep 5
fi

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="