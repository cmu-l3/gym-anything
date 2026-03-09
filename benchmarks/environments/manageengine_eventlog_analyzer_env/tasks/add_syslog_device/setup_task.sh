#!/bin/bash
# Setup for "add_syslog_device" task
# Ensures EventLog Analyzer is running and Firefox is open on the Device Management page

echo "=== Setting up Add Syslog Device task ==="

# Source shared utilities
# Do NOT use set -euo pipefail (cross-cutting pattern #25)
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Ensure EventLog Analyzer is running
wait_for_eventlog_analyzer

# Record the current number of devices for verification
echo "Recording initial device count for verification..."
INITIAL_COUNT=$(ela_api_call "/event/api/v1/devices" "GET" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('devices', d.get('data', []))))" \
    2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_device_count
echo "Initial device count: $INITIAL_COUNT"

# Navigate to dashboard first (AppHome.do deep links fail as direct URLs due to SPA routing)
# Go via AppsHome.do (main app) then click Settings tab to reach Device Management
ensure_firefox_on_ela "/event/AppsHome.do#/home/dashboard/0"
sleep 4

# Dismiss any "What's New" or onboarding dialog with Escape
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape
sleep 1

# Focus Firefox and click Settings tab at (618, 203) in 1920x1080
WID=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -ia "$WID" 2>/dev/null || true
fi
sleep 0.5
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool mousemove 618 203 click 1
echo "Clicked Settings tab"
sleep 4

# Click Devices card at (197, 339) in 1920x1080
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool mousemove 197 339 click 1
echo "Clicked Devices"
sleep 3

# Click Syslog Devices tab at (555, 276) in 1920x1080
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool mousemove 555 276 click 1
echo "Clicked Syslog Devices tab"
sleep 2

# Take initial screenshot for evidence
take_screenshot /tmp/add_syslog_device_start.png

echo ""
echo "=== Add Syslog Device Task Ready ==="
echo ""
echo "Instructions:"
echo "  EventLog Analyzer Settings > Device Management is open in Firefox."
echo "  You are logged in as admin."
echo "  Click the 'Syslog Devices' tab."
echo "  Click '+ Add Device/s' button."
echo "  Add a new Syslog device:"
echo "    - Device Name: ubuntu-server"
echo "    - IP Address: 127.0.0.1"
echo "    - Device Type: Linux"
echo ""
