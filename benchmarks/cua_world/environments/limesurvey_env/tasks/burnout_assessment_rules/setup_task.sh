#!/bin/bash
echo "=== Setting up Burnout Assessment Rules Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure LimeSurvey is ready
echo "Waiting for LimeSurvey..."
for i in {1..30}; do
    if curl -s http://localhost/index.php/admin > /dev/null; then
        echo "LimeSurvey is responsive."
        break
    fi
    sleep 2
done

# Clean up any existing surveys that might conflict (to ensure fresh start)
# We delete surveys containing "Burnout" or "CBI" to prevent scoring previous runs
echo "Cleaning up old surveys..."
docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -e \
    "DELETE FROM lime_surveys WHERE sid IN (SELECT surveyls_survey_id FROM lime_surveys_languagesettings WHERE surveyls_title LIKE '%Burnout%' OR surveyls_title LIKE '%CBI%');" 2>/dev/null || true

# Record initial survey count
INITIAL_COUNT=$(get_survey_count)
echo "$INITIAL_COUNT" > /tmp/initial_survey_count
echo "Initial survey count: $INITIAL_COUNT"

# Ensure Firefox is open to the admin page
if ! pgrep -f "firefox" > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox -profile /home/ga/.mozilla/firefox/default.profile 'http://localhost/index.php/admin' &"
    sleep 10
else
    # Just focus and reload if already open
    focus_firefox
    DISPLAY=:1 xdotool key F5
    sleep 3
fi

# Maximize window
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="