#!/bin/bash
echo "=== Setting up PHQ-9 Clinical Survey Task ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$path" 2>/dev/null || DISPLAY=:1 scrot "$path" 2>/dev/null || true
    }
fi

# Wait for LimeSurvey to be ready
for i in $(seq 1 20); do
    HTTP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/index.php/admin 2>/dev/null || echo "000")
    if [ "$HTTP" = "200" ] || [ "$HTTP" = "302" ] || [ "$HTTP" = "303" ]; then
        echo "LimeSurvey ready (HTTP $HTTP)"
        break
    fi
    echo "Waiting for LimeSurvey... attempt $i (HTTP $HTTP)"
    sleep 5
done

# Remove any pre-existing PHQ-9 surveys to start clean
python3 << 'PYEOF'
import json, urllib.request, sys

BASE = "http://localhost/index.php/admin/remotecontrol"

def api(method, params):
    data = json.dumps({"method": method, "params": params, "id": 1}).encode()
    req = urllib.request.Request(BASE, data=data, headers={"Content-Type": "application/json"})
    try:
        return json.loads(urllib.request.urlopen(req, timeout=15).read())
    except Exception as e:
        return {"result": None, "error": str(e)}

resp = api("get_session_key", ["admin", "Admin123!"])
session = resp.get("result", "")
if not session or "error" in str(session).lower():
    print(f"Could not get session key: {session}")
    sys.exit(0)

surveys = api("list_surveys", [session]).get("result", [])
if isinstance(surveys, list):
    for s in surveys:
        title = s.get("surveyls_title", "").lower()
        if "phq" in title or "mental health screening" in title:
            sid = s.get("sid")
            result = api("delete_survey", [session, sid])
            print(f"Removed existing survey '{s.get('surveyls_title')}' (SID={sid}): {result.get('result')}")

api("release_session_key", [session])
print("Cleanup complete")
PYEOF

# Record baseline survey count
INITIAL_SURVEY_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_surveys" 2>/dev/null || echo "0")
INITIAL_SURVEY_COUNT=${INITIAL_SURVEY_COUNT:-0}
echo "$INITIAL_SURVEY_COUNT" > /tmp/phq9_initial_survey_count
echo "Initial survey count: $INITIAL_SURVEY_COUNT"

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
echo "Task start recorded: $(cat /tmp/task_start_timestamp)"

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

# Ensure Firefox is open to LimeSurvey admin
DISPLAY=:1 wmctrl -a Firefox 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers "http://localhost/index.php/admin" 2>/dev/null || true
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 3

echo ""
echo "=== Setup Complete ==="
echo "Starting state: No PHQ-9 survey exists."
echo "Agent must create survey from scratch with 3 groups, Array question, mandatory, anonymized, and activate."
