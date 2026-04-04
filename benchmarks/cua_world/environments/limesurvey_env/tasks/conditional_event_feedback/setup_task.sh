#!/bin/bash
set -e
echo "=== Setting up Conditional Event Feedback Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Wait for LimeSurvey to be ready
echo "Checking LimeSurvey availability..."
wait_for_limesurvey() {
    for i in {1..30}; do
        if curl -s http://localhost/index.php/admin > /dev/null; then
            return 0
        fi
        sleep 2
    done
    return 1
}
wait_for_limesurvey || echo "WARNING: LimeSurvey might not be ready yet"

# Ensure Firefox is running and focused on LimeSurvey admin
echo "Launching Firefox..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/index.php/admin' &"
    sleep 5
fi

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i -E "(firefox|limesurvey|mozilla)" > /dev/null; then
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
focus_firefox

# Record initial survey count (should be 0 or low)
INITIAL_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_surveys" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_survey_count

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="