#!/bin/bash
set -e
echo "=== Setting up Label Set Concept Test task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Helper for DB queries
DB_QUERY() {
    docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
}

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial counts for anti-gaming detection
INITIAL_SURVEY_COUNT=$(DB_QUERY "SELECT COUNT(*) FROM lime_surveys" || echo "0")
echo "$INITIAL_SURVEY_COUNT" > /tmp/initial_survey_count.txt

INITIAL_LABELSET_COUNT=$(DB_QUERY "SELECT COUNT(*) FROM lime_labelsets" || echo "0")
echo "$INITIAL_LABELSET_COUNT" > /tmp/initial_labelset_count.txt

echo "Initial surveys: $INITIAL_SURVEY_COUNT"
echo "Initial label sets: $INITIAL_LABELSET_COUNT"

# Ensure Firefox is running with LimeSurvey admin
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox -profile /home/ga/.mozilla/firefox/default.profile 'http://localhost/index.php/admin' &"
    sleep 5
fi

# Wait for Firefox window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i -E "(firefox|mozilla|limesurvey)" > /dev/null; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize and focus Firefox
DISPLAY=:1 wmctrl -r Firefox -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a Firefox 2>/dev/null || true
sleep 2

# Ensure we are logged in or at login screen
# (The environment usually handles auto-login or session persistence, 
# but navigating to admin root ensures we start at a known place)
su - ga -c "DISPLAY=:1 xdotool key ctrl+l" 2>/dev/null || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type 'http://localhost/index.php/admin'" 2>/dev/null || true
su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="