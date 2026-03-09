#!/bin/bash
echo "=== Setting up Customer Experience Journey Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time

# Helper to execute SQL
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

# Clean up any existing surveys with similar titles to ensure a clean slate
echo "Cleaning up old surveys..."
# We use Python for cleaner API interaction to delete surveys
python3 << 'PYEOF'
import json, urllib.request, sys

BASE = "http://localhost/index.php/admin/remotecontrol"
HEADERS = {"Content-Type": "application/json"}

def rpc(method, params):
    data = json.dumps({"method": method, "params": params, "id": 1}).encode()
    req = urllib.request.Request(BASE, data=data, headers=HEADERS)
    try:
        resp = urllib.request.urlopen(req, timeout=5)
        return json.loads(resp.read())
    except Exception as e:
        return {"error": str(e)}

# Get Session
s_key = rpc("get_session_key", ["admin", "Admin123!"]).get("result")
if not s_key or "error" in str(s_key):
    print("Could not get session key, skipping cleanup")
    sys.exit(0)

# List Surveys
surveys = rpc("list_surveys", [s_key, "admin"]).get("result", [])
if isinstance(surveys, list):
    for s in surveys:
        title = s.get("surveyls_title", "").lower()
        if "customer experience" in title or "journey" in title:
            print(f"Deleting existing survey: {title} (ID: {s.get('sid')})")
            rpc("delete_survey", [s_key, s.get("sid")])

rpc("release_session_key", [s_key])
PYEOF

# Ensure Firefox is running and focused
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
    sleep 5
fi

# Focus and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i -E "(firefox|limesurvey|mozilla)"; then
        WID=$(DISPLAY=:1 wmctrl -l | grep -i -E "(firefox|limesurvey|mozilla)" | head -1 | awk '{print $1}')
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
        DISPLAY=:1 wmctrl -i -a "$WID"
        break
    fi
    sleep 1
done

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="