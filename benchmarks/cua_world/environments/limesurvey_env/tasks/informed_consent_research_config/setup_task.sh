#!/bin/bash
set -e

echo "=== Setting up Informed Consent Research Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure LimeSurvey is running
if ! docker ps | grep -q limesurvey-app; then
    echo "Starting LimeSurvey containers..."
    cd /home/ga/limesurvey
    docker-compose up -d
    wait_for_limesurvey
fi

# Clean up any previous attempts (surveys with similar titles) to prevent confusion
echo "Cleaning up previous surveys..."
limesurvey_query "DELETE FROM lime_surveys WHERE sid IN (SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE LOWER(surveyls_title) LIKE '%social media%')" 2>/dev/null || true
limesurvey_query "DELETE FROM lime_surveys_languagesettings WHERE LOWER(surveyls_title) LIKE '%social media%'" 2>/dev/null || true

# Record initial survey count
INITIAL_COUNT=$(get_survey_count)
echo "$INITIAL_COUNT" > /tmp/initial_survey_count
echo "Initial survey count: $INITIAL_COUNT"

# Ensure Firefox is running and focused
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
    sleep 5
else
    # Check if Firefox is responding
    if ! curl -s --head http://localhost/index.php/admin > /dev/null; then
         echo "Refreshing Firefox..."
         DISPLAY=:1 xdotool key F5
    fi
fi

# Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="