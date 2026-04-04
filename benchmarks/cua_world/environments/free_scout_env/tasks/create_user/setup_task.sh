#!/bin/bash
echo "=== Setting up create_user task ==="

source /workspace/scripts/task_utils.sh

# Record initial user count
INITIAL_COUNT=$(get_user_count)
echo "$INITIAL_COUNT" > /tmp/initial_user_count
echo "Initial user count: $INITIAL_COUNT"

# Ensure Firefox is running
if ! pgrep -f firefox > /dev/null; then
    DISPLAY=:1 firefox 'http://localhost:8080' > /tmp/firefox.log 2>&1 &
    sleep 5
fi

wait_for_window "firefox|mozilla|freescout" 30
focus_firefox
navigate_to_url "http://localhost:8080"
sleep 3

take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
