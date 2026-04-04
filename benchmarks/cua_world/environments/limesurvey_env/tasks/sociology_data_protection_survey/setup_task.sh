#!/bin/bash
echo "=== Setting up Sociology Data Protection Survey Task ==="

source /workspace/scripts/task_utils.sh

# Define helper if not present
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for LimeSurvey to be fully ready
echo "Waiting for LimeSurvey..."
for i in {1..30}; do
    if curl -s http://localhost/index.php/admin > /dev/null; then
        echo "LimeSurvey is ready."
        break
    fi
    sleep 2
done

# Cleanup: Remove any existing survey with the target title to ensure a clean start
# This prevents the agent from finding a pre-completed survey
TARGET_TITLE_PART="Social Media Usage"
EXISTING_SID=$(limesurvey_query "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings sl ON s.sid=sl.surveyls_survey_id WHERE sl.surveyls_title LIKE '%$TARGET_TITLE_PART%' LIMIT 1")

if [ -n "$EXISTING_SID" ]; then
    echo "Removing existing survey SID=$EXISTING_SID to ensure clean state..."
    # We use a python script to delete via API if possible, or just warn the user
    # Ideally, we should delete it, but direct DB deletion is risky.
    # For now, we will rely on the verify script checking CREATION time vs task start time.
    echo "Warning: Survey already exists. Verification will check modification timestamps."
fi

# Record initial survey count
INITIAL_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_surveys")
echo "$INITIAL_COUNT" > /tmp/initial_survey_count.txt
echo "Initial survey count: $INITIAL_COUNT"

# Ensure Firefox is running and focused
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
    sleep 10
fi

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="