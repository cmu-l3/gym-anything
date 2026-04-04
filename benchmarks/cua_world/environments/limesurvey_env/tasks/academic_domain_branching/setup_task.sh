#!/bin/bash
set -e
echo "=== Setting up Academic Domain Branching Task ==="

source /workspace/scripts/task_utils.sh

# Define helper if not present
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
fi

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure LimeSurvey is running
echo "Waiting for LimeSurvey..."
for i in {1..30}; do
    if curl -s http://localhost/index.php/admin >/dev/null; then
        echo "LimeSurvey is ready."
        break
    fi
    sleep 2
done

# Clean up any existing surveys with the specific title to prevent confusion
echo "Cleaning up old surveys..."
limesurvey_query "DELETE FROM lime_surveys WHERE sid IN (SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE surveyls_title LIKE '%National Research Collaboration%')" 2>/dev/null || true
limesurvey_query "DELETE FROM lime_surveys_languagesettings WHERE surveyls_title LIKE '%National Research Collaboration%'" 2>/dev/null || true

# Record initial survey count
INITIAL_COUNT=$(get_survey_count)
echo "$INITIAL_COUNT" > /tmp/initial_survey_count

# Setup Firefox
echo "Launching Firefox..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
    sleep 5
fi

# Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox"; then
        DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="