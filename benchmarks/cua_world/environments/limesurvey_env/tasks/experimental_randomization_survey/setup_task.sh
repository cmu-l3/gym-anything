#!/bin/bash
set -e
echo "=== Setting up Framing Effect Experiment Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial survey count for anti-gaming
INITIAL_COUNT=$(get_survey_count)
echo "$INITIAL_COUNT" > /tmp/initial_survey_count.txt
echo "Initial survey count: $INITIAL_COUNT"

# Ensure LimeSurvey database is ready
wait_for_mysql() {
    local timeout=30
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if docker exec limesurvey-db mysqladmin ping -h localhost -u root -plimesurvey_root_pw 2>/dev/null; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    return 1
}
wait_for_mysql || echo "Warning: MySQL wait timed out, proceeding anyway..."

# Ensure Firefox is open to the admin page
focus_firefox
if ! pgrep -f "firefox" > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox -profile /home/ga/.mozilla/firefox/default.profile 'http://localhost/index.php/admin' &"
    sleep 10
else
    # Navigate to admin page if already open
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost/index.php/admin"
    DISPLAY=:1 xdotool key Return
    sleep 3
fi

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="