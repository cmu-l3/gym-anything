#!/bin/bash
echo "=== Setting up Event Cost Estimator Task ==="

source /workspace/scripts/task_utils.sh

# Fallback for query utility if not in path
if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$path" 2>/dev/null || DISPLAY=:1 scrot "$path" 2>/dev/null || true
    }
fi

# Record start time
date +%s > /tmp/task_start_time.txt

# Record initial survey count
INITIAL_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_surveys" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_survey_count
echo "Initial survey count: $INITIAL_COUNT"

# Ensure Firefox is running and focused on LimeSurvey Admin
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
    sleep 10
fi

# Focus Firefox
focus_firefox
sleep 1
DISPLAY=:1 xdotool key ctrl+l 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool type --clearmodifiers "http://localhost/index.php/admin" 2>/dev/null || true
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 5

# Dismiss any potential popups (welcome tours, etc.)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="