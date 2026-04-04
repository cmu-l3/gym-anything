#!/bin/bash
set -e
echo "=== Setting up Product Concept Survey Config Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for LimeSurvey to be ready
wait_for_limesurvey_api() {
    local timeout=120
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        HTTP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/index.php/admin 2>/dev/null || echo "000")
        if [ "$HTTP" = "200" ] || [ "$HTTP" = "302" ]; then
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done
    return 1
}
wait_for_limesurvey_api || echo "WARNING: LimeSurvey might not be ready"

# Create the survey in the initial state using Python
# We create a survey with "Group by Group" (wrong), "Show prev" (wrong), etc.
echo "Creating initial survey state..."
python3 << 'PYEOF'
import json, urllib.request, sys, time

BASE = "http://localhost/index.php/admin/remotecontrol"
TARGET_TITLE = "Sparkling Water Concept Test - Wave 3"

def api(method, params):
    data = json.dumps({"method": method, "params": params, "id": 1}).encode()
    req = urllib.request.Request(BASE, data=data, headers={"Content-Type": "application/json"})
    try:
        return json.loads(urllib.request.urlopen(req, timeout=10).read())
    except Exception as e:
        return {"result": None, "error": str(e)}

# Get session
session = None
for i in range(10):
    res = api("get_session_key", ["admin", "Admin123!"])
    if isinstance(res.get("result"), str) and "error" not in str(res.get("result")):
        session = res["result"]
        break
    time.sleep(2)

if not session:
    print("Failed to get session key")
    sys.exit(1)

# Clean up existing survey if it exists
surveys = api("list_surveys", [session]).get("result", [])
if isinstance(surveys, list):
    for s in surveys:
        if s.get("surveyls_title") == TARGET_TITLE:
            api("delete_survey", [session, s["sid"]])
            print(f"Deleted existing survey {s['sid']}")

# Create new survey with DEFAULT settings (which agent must change)
# format: 'G' (Group by Group) -> Agent must change to 'S'
create_res = api("add_survey", [session, 0, TARGET_TITLE, "en", "G"])
sid = create_res.get("result")
print(f"Created survey SID: {sid}")

if isinstance(sid, int):
    # Set other default settings explicitly to ensure they are wrong
    # We use set_survey_properties. 
    # Settings to be fixed by agent:
    # showprogress: N (default) -> Y
    # allowprev: Y (default) -> N
    # shownoanswer: Y (default) -> N
    # emailnotificationto: "" -> "concept-alerts@..."
    
    props = {
        "showprogress": "N",
        "allowprev": "Y",
        "shownoanswer": "Y",
        "emailnotificationto": ""
    }
    api("set_survey_properties", [session, sid, props])

    # Add some dummy groups and questions to make it realistic
    g1 = api("add_group", [session, sid, "Concept Exposure", ""]).get("result")
    g2 = api("add_group", [session, sid, "Purchase Intent", ""]).get("result")
    g3 = api("add_group", [session, sid, "Demographics", ""]).get("result")

    # Add a text display question for concept
    api("add_question", [session, sid, g1, "en", {"title": "CONCEPT", "type": "X", "question": "Please review the image below..."}])
    # Add a purchase intent question
    api("add_question", [session, sid, g2, "en", {"title": "PI", "type": "L", "question": "How likely are you to buy this?"}])
    
    print("Survey structure populated")

api("release_session_key", [session])
PYEOF

# Record initial state for verification (snapshot of settings)
# We just record the timestamp; verifier checks the final DB state
date +%s > /tmp/task_start_timestamp

# Open Firefox to Admin Login
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
    sleep 5
fi

# Focus Firefox and Maximize
for i in {1..30}; do
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox" | awk '{print $1}' | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
        DISPLAY=:1 wmctrl -ia "$WID"
        break
    fi
    sleep 1
done

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="