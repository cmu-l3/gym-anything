#!/bin/bash
echo "=== Setting up Modify Device Properties task ==="

# Source shared utilities
# Do NOT use set -euo pipefail (cross-cutting pattern #25)
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure EventLog Analyzer is running
wait_for_eventlog_analyzer 600

# ==============================================================================
# Record Initial State
# ==============================================================================
echo "Recording initial device state..."

# We attempt to fetch the device details for 127.0.0.1 via API
# This helps us verify later that the values actually changed
INITIAL_STATE_FILE="/tmp/initial_device_state.json"

# Python script to fetch device details via requests (using task_utils helper would be cleaner if it returned raw JSON)
# We'll use a small inline python script to leverage the ela_api_call logic
cat > /tmp/fetch_device_details.py << 'PYEOF'
import json
import sys
import subprocess

# Helper to run curl command similar to ela_api_call
def get_devices():
    # We rely on the system's ela-api utility or curl wrapper
    # But since we are inside setup_task, we can use the cookies from task_utils if we sourced them? 
    # Actually, let's just use the `ela-api` utility created in the environment install script.
    try:
        # Calls the /event/api/v1/devices endpoint
        cmd = ["/usr/local/bin/ela-api", "/event/api/v1/devices", "GET"]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            return None
        return json.loads(result.stdout)
    except Exception as e:
        sys.stderr.write(str(e))
        return None

data = get_devices()
device_info = {}

if data:
    # Handle different possible API response structures
    devices = data.get("devices", data.get("data", []))
    for d in devices:
        # Match localhost or 127.0.0.1
        ip = d.get("ip", "")
        if ip == "127.0.0.1" or ip == "localhost":
            device_info = {
                "display_name": d.get("displayName", d.get("hostName", "")),
                "description": d.get("description", ""),
                "location": d.get("location", "")
            }
            break

print(json.dumps(device_info))
PYEOF

python3 /tmp/fetch_device_details.py > "$INITIAL_STATE_FILE" 2>/dev/null
echo "Initial state saved to $INITIAL_STATE_FILE"
cat "$INITIAL_STATE_FILE"

# ==============================================================================
# Browser Navigation
# ==============================================================================
# Navigate to dashboard first to ensure session is active
ensure_firefox_on_ela "/event/AppsHome.do#/home/dashboard/0"
sleep 5

# Dismiss any "What's New" or onboarding dialog with Escape
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape 2>/dev/null || true
sleep 1

# Navigate to Settings > Devices
# We use xdotool to click "Settings" then "Devices" to ensure the agent starts 
# in the right context, similar to the add_syslog_device task.
# Coordinates assume 1920x1080 maximized window.

# 1. Click Settings tab (approx 618, 203)
echo "Navigating to Settings..."
WID=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -ia "$WID" 2>/dev/null || true
fi
sleep 1
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool mousemove 618 203 click 1
sleep 4

# 2. Click Devices/Managed Devices (approx 197, 339)
echo "Navigating to Managed Devices..."
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool mousemove 197 339 click 1
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="