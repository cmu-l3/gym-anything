#!/bin/bash
set -e
echo "=== Setting up configure_system_announcement task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Jenkins to be available
echo "Waiting for Jenkins API..."
wait_for_jenkins_api 60

# Record initial state: capture current markup formatter and system message
echo "Recording initial state..."

# Get current markup formatter class via Groovy
INITIAL_FORMATTER=$(curl -s -u "$JENKINS_USER:$JENKINS_PASS" \
  --data-urlencode "script=println Jenkins.instance.markupFormatter.class.name" \
  "$JENKINS_URL/scriptText" 2>/dev/null || echo "unknown")
echo "$INITIAL_FORMATTER" > /tmp/initial_markup_formatter.txt
echo "Initial markup formatter: $INITIAL_FORMATTER"

# Get current system message
INITIAL_MSG=$(curl -s -u "$JENKINS_USER:$JENKINS_PASS" \
  "$JENKINS_URL/api/json" 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('description', '') or '')
except:
    print('')
" 2>/dev/null || echo "")
echo "$INITIAL_MSG" > /tmp/initial_system_message.txt
echo "Initial system message length: ${#INITIAL_MSG}"

# Ensure markup formatter is Plain text (the default) and system message is empty
# Reset it via Groovy to guarantee clean state
echo "Ensuring clean initial state (Plain text formatter, no system message)..."
curl -s -u "$JENKINS_USER:$JENKINS_PASS" \
  --data-urlencode "script=
import hudson.markup.EscapedMarkupFormatter
Jenkins.instance.setMarkupFormatter(new EscapedMarkupFormatter())
Jenkins.instance.setSystemMessage('')
Jenkins.instance.save()
println 'Reset complete'
" "$JENKINS_URL/scriptText" 2>/dev/null || echo "WARNING: Could not reset state"

sleep 2

# Verify reset
VERIFY_FORMATTER=$(curl -s -u "$JENKINS_USER:$JENKINS_PASS" \
  --data-urlencode "script=println Jenkins.instance.markupFormatter.class.name" \
  "$JENKINS_URL/scriptText" 2>/dev/null || echo "unknown")
echo "Verified formatter after reset: $VERIFY_FORMATTER"

# Ensure Firefox is open and focused on Jenkins dashboard
echo "Ensuring Firefox is on Jenkins dashboard..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    # Navigate to Jenkins dashboard
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type --delay 30 "http://localhost:8080/"
    DISPLAY=:1 xdotool key Return
    sleep 3
else
    echo "Firefox not found, launching..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080/' &" 2>/dev/null
    sleep 5
    WID=$(get_firefox_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi
fi

# Dismiss any popups
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial state screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "Task: Configure system announcement with HTML markup"
echo "Initial formatter: Plain text (EscapedMarkupFormatter)"
echo "Initial system message: (empty)"