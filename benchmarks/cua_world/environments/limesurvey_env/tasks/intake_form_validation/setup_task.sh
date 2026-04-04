#!/bin/bash
echo "=== Setting up Intake Form Validation Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial survey count
INITIAL_SURVEY_COUNT=$(get_survey_count)
echo "$INITIAL_SURVEY_COUNT" > /tmp/initial_survey_count.txt
echo "Initial survey count: $INITIAL_SURVEY_COUNT"

# Ensure Firefox is running and focused on LimeSurvey
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
    sleep 5
fi

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Firefox" > /dev/null; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="