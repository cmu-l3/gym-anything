#!/bin/bash
echo "=== Setting up Custom Screen Definition task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if type wait_for_cosmos_api &>/dev/null; then
    if ! wait_for_cosmos_api 60; then
        echo "WARNING: COSMOS API not ready, continuing anyway"
    fi
fi

# Remove stale output files
rm -f /home/ga/Desktop/screen_report.json 2>/dev/null || true
rm -f /tmp/custom_screen_definition_result.json 2>/dev/null || true

# Remove any existing thermal_overview screen to ensure clean state
find /home/ga/cosmos/plugins -type f -iname "*thermal_overview*.txt" -delete 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/custom_screen_definition_start_ts
echo "Task start recorded: $(cat /tmp/custom_screen_definition_start_ts)"

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
OPENC3_URL=${OPENC3_URL:-"http://localhost:2900"}
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$OPENC3_URL/tools/tlmviewer' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
if type wait_for_window &>/dev/null; then
    if ! wait_for_window "firefox\|mozilla\|openc3\|cosmos" 30; then
        echo "WARNING: Firefox window not detected"
    fi
fi

# Navigate to Telemetry Viewer if not there
echo "Navigating to Telemetry Viewer..."
if type navigate_to_url &>/dev/null; then
    navigate_to_url "$OPENC3_URL/tools/tlmviewer"
    sleep 5
fi

# Focus and maximize the Firefox window
if type get_firefox_window_id &>/dev/null; then
    WID=$(get_firefox_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        sleep 1
    fi
fi

# Take initial screenshot
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/custom_screen_definition_start.png
else
    DISPLAY=:1 scrot /tmp/custom_screen_definition_start.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/custom_screen_definition_start.png 2>/dev/null || true
fi

echo "=== Custom Screen Definition Setup Complete ==="
echo ""
echo "Task: Create a custom telemetry screen named THERMAL_OVERVIEW for the INST target."
echo "Confirmation must be written to: /home/ga/Desktop/screen_report.json"
echo ""