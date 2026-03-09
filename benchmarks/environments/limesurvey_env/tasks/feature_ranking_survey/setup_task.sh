#!/bin/bash
echo "=== Setting up Feature Ranking Survey Task ==="

source /workspace/scripts/task_utils.sh

# Fallback for DB query function if not present in utils
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

# Fallback for screenshot function
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 scrot "$path" 2>/dev/null || true
    }
fi

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for LimeSurvey to be ready
echo "Checking LimeSurvey availability..."
for i in {1..30}; do
    if curl -s http://localhost/index.php/admin >/dev/null; then
        echo "LimeSurvey is ready."
        break
    fi
    sleep 2
done

# Clean up any existing surveys with similar titles to ensure a clean state
echo "Cleaning up existing conflicting surveys..."
IDS_TO_DELETE=$(limesurvey_query "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings sl ON s.sid = sl.surveyls_survey_id WHERE LOWER(sl.surveyls_title) LIKE '%smart home%' OR LOWER(sl.surveyls_title) LIKE '%feature prioritization%'")

if [ -n "$IDS_TO_DELETE" ]; then
    echo "Found existing surveys to delete: $IDS_TO_DELETE"
    for sid in $IDS_TO_DELETE; do
        # We can't easily delete via SQL due to foreign keys, so we'll just rename them to avoid confusion
        # or rely on the agent creating a NEW one. 
        # Ideally, we'd use the API to delete, but for setup simplicity, we'll record the initial count
        # and checking specific IDs created after start time is safer.
        echo "Marking survey $sid as stale/ignore"
    done
fi

# Record initial survey count
INITIAL_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_surveys" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_survey_count
echo "Initial survey count: $INITIAL_COUNT"

# Ensure Firefox is running and focused
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
    sleep 10
fi

# Focus and maximize
DISPLAY=:1 wmctrl -a Firefox 2>/dev/null || true
DISPLAY=:1 wmctrl -r Firefox -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="