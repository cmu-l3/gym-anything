#!/bin/bash
set -e
echo "=== Setting up BRFSS CATI Survey Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Fallback query function if utils not loaded
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

# Wait for LimeSurvey to be ready
echo "Checking LimeSurvey availability..."
for i in {1..30}; do
    if curl -s http://localhost/index.php/admin >/dev/null; then
        echo "LimeSurvey is ready."
        break
    fi
    sleep 2
done

# Clean up any existing surveys with "BRFSS" or "Health Interview" in the title
# This ensures the agent creates a NEW survey and we verify the correct one.
echo "Cleaning up old surveys..."
# We use Python for complex API/DB logic to delete specific surveys
python3 << 'PYEOF'
import json
import subprocess

def run_query(query):
    cmd = ["docker", "exec", "limesurvey-db", "mysql", "-u", "limesurvey", "-plimesurvey_pass", "limesurvey", "-N", "-e", query]
    try:
        return subprocess.check_output(cmd).decode('utf-8').strip()
    except:
        return ""

# Find surveys to delete
sql = "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings ls ON s.sid = ls.surveyls_survey_id WHERE LOWER(ls.surveyls_title) LIKE '%brfss%' OR LOWER(ls.surveyls_title) LIKE '%health interview%'"
sids = run_query(sql).split('\n')

for sid in sids:
    if sid.strip():
        print(f"Deleting old survey SID: {sid}")
        # Delete from core tables
        run_query(f"DELETE FROM lime_surveys WHERE sid={sid}")
        run_query(f"DELETE FROM lime_surveys_languagesettings WHERE surveyls_survey_id={sid}")
        run_query(f"DELETE FROM lime_questions WHERE sid={sid}")
        run_query(f"DELETE FROM lime_groups WHERE sid={sid}")
PYEOF

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Start Firefox and navigate to Admin login
echo "Starting Firefox..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
else
    # If running, just go to the URL
    su - ga -c "DISPLAY=:1 firefox -new-window 'http://localhost/index.php/admin' &"
fi

# Wait for window and maximize
sleep 5
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox" | awk '{print $1}' | head -n 1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
    DISPLAY=:1 wmctrl -i -a "$WID"
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="