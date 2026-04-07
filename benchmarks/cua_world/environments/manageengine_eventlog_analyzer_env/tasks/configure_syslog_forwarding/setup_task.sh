#!/bin/bash
# Setup for "configure_syslog_forwarding" task

echo "=== Setting up Configure Syslog Forwarding task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for EventLog Analyzer to be fully ready (web UI accessible)
wait_for_eventlog_analyzer 900

# Record initial state: count of forwarding rules in DB
# We try a few likely table names since schema versions vary
echo "Recording initial forwarding rules..."
INITIAL_COUNT="0"
for table in "SyslogForwarding" "SL_SyslogForwarding" "ForwardingList"; do
    COUNT=$(ela_db_query "SELECT COUNT(*) FROM $table" 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$COUNT" ]; then
        INITIAL_COUNT=$COUNT
        echo "Found table $table with $COUNT rules"
        break
    fi
done
echo "$INITIAL_COUNT" > /tmp/initial_forwarding_count.txt

# Ensure Firefox is open on the EventLog Analyzer dashboard
# We launch to the dashboard; the agent must find the Settings/Admin tab
ensure_firefox_on_ela "/event/index.do"
sleep 5

# Focus and maximize
WID=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any popup dialogs (e.g., 'What's New')
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "Instructions:"
echo "1. Navigate to Settings / Admin"
echo "2. Find Syslog Forwarding configuration"
echo "3. Configure forwarding to:"
echo "   - IP: 10.200.50.25"
echo "   - Port: 1514"
echo "   - Protocol: UDP"