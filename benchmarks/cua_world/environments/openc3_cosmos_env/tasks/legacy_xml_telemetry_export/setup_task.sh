#!/bin/bash
echo "=== Setting up Legacy XML Telemetry Export task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if type wait_for_cosmos_api &>/dev/null; then
    wait_for_cosmos_api 60 || echo "WARNING: COSMOS API not ready, continuing anyway"
fi

# Remove stale output files FIRST to prevent false positives
rm -f /home/ga/Desktop/legacy_telemetry_export.xml 2>/dev/null || true
rm -f /tmp/legacy_xml_telemetry_export_result.json 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/legacy_xml_export_start_ts
echo "Task start recorded: $(cat /tmp/legacy_xml_export_start_ts)"

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
OPENC3_URL=${OPENC3_URL:-"http://localhost:2900"}
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$OPENC3_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
if type wait_for_window &>/dev/null; then
    wait_for_window "firefox\|mozilla\|openc3\|cosmos" 30 || echo "WARNING: Firefox window not detected"
fi

# Maximize and focus the Firefox window
if type get_firefox_window_id &>/dev/null; then
    WID=$(get_firefox_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        sleep 1
    fi
else
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/legacy_xml_export_start.png
else
    DISPLAY=:1 scrot /tmp/legacy_xml_export_start.png 2>/dev/null || true
fi

echo "=== Legacy XML Telemetry Export Setup Complete ==="
echo ""
echo "Task: Sample live telemetry 10 times (1s intervals) and output to XML."
echo "Output must be written to: /home/ga/Desktop/legacy_telemetry_export.xml"
echo ""