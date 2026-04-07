#!/bin/bash
set -e

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Configure Site Security Policies Task ==="

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Record initial configuration state (Anti-gaming baseline)
# We record the values of the settings we expect to change.
# This helps us verify that the agent actually changed them, rather than them matching by coincidence (unlikely for these specific values).
echo "Recording initial configuration state..."
CONFIG_KEYS=(
    "passwordpolicy"
    "minpasswordlength"
    "minpassworddigits"
    "minpasswordlower"
    "minpasswordupper"
    "minpasswordnonalphanum"
    "maxconsecutiveidentchars"
    "lockoutthreshold"
    "lockoutwindow"
    "lockoutduration"
    "sessiontimeout"
)

# Create a JSON object for initial state
INITIAL_JSON="{"
first=true
for key in "${CONFIG_KEYS[@]}"; do
    # Fetch value from mdl_config
    val=$(moodle_query "SELECT value FROM mdl_config WHERE name='$key'" 2>/dev/null || echo "")
    
    if [ "$first" = true ]; then
        first=false
    else
        INITIAL_JSON="$INITIAL_JSON,"
    fi
    INITIAL_JSON="$INITIAL_JSON \"$key\": \"$val\""
done
INITIAL_JSON="$INITIAL_JSON }"

echo "$INITIAL_JSON" > /tmp/initial_config_state.json
echo "Initial state recorded: $INITIAL_JSON"

# 3. Ensure Firefox is running and focused
MOODLE_URL="http://localhost/"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MOODLE_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|Moodle" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# 4. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="