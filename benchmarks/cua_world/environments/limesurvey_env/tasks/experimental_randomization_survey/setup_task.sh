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

# Ensure Firefox is open to the admin page — use restart_firefox from task_utils
# to avoid "Firefox is already running" lock file conflicts
restart_firefox "http://localhost/index.php/admin"

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="