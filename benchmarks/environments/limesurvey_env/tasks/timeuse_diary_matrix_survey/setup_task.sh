#!/bin/bash
echo "=== Setting up Time-Use Diary Survey Task ==="

source /workspace/scripts/task_utils.sh

# Function to run SQL safely
db_query() {
    docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
}

# Wait for LimeSurvey to be fully ready
echo "Checking LimeSurvey availability..."
for i in {1..30}; do
    if curl -s http://localhost/index.php/admin > /dev/null; then
        echo "LimeSurvey is reachable."
        break
    fi
    sleep 2
done

# Cleanup: Delete any existing surveys with similar titles to ensure a fresh start
echo "Cleaning up previous surveys..."
IDS=$(db_query "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings ls ON s.sid = ls.surveyls_survey_id WHERE LOWER(ls.surveyls_title) LIKE '%time%allocation%' OR LOWER(ls.surveyls_title) LIKE '%student%life%'")

for sid in $IDS; do
    if [ -n "$sid" ]; then
        echo "Deleting old survey SID: $sid"
        # We delete from main table; cascade should handle the rest in a real DB, 
        # but for LimeSurvey we often need to be careful. 
        # For setup simplicity, we'll try to use the API or just drop the row if we can't use API easily.
        # Since we have the API script pattern from other tasks, let's use a Python cleanup script.
        :
    fi
done

# Python script to clean up specific surveys via API (safer than raw SQL)
python3 << 'PYEOF'
import json, urllib.request, sys

BASE = "http://localhost/index.php/admin/remotecontrol"

def api(method, params):
    data = json.dumps({"method": method, "params": params, "id": 1}).encode()
    req = urllib.request.Request(BASE, data=data, headers={"Content-Type": "application/json"})
    try:
        return json.loads(urllib.request.urlopen(req, timeout=10).read())
    except Exception as e:
        return {"result": None, "error": str(e)}

# Get session
resp = api("get_session_key", ["admin", "Admin123!"])
session = resp.get("result")
if not isinstance(session, str) or "error" in str(session).lower():
    print("Could not get session for cleanup. Skipping API cleanup.")
    sys.exit(0)

# List and delete
surveys = api("list_surveys", [session]).get("result", [])
if isinstance(surveys, list):
    for s in surveys:
        title = s.get("surveyls_title", "").lower()
        if "time" in title and "allocation" in title:
            print(f"Deleting survey {s['sid']}...")
            api("delete_survey", [session, s["sid"]])

api("release_session_key", [session])
PYEOF

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial survey count
INITIAL_COUNT=$(db_query "SELECT COUNT(*) FROM lime_surveys")
echo "$INITIAL_COUNT" > /tmp/initial_survey_count.txt

# Start Firefox focused on admin page
echo "Launching Firefox..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
    sleep 5
fi

# Maximize and focus
focus_firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="