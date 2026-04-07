#!/bin/bash
echo "=== Setting up Asynchronous Telemetry Sensor Fusion task ==="

source /workspace/scripts/task_utils.sh

# Wait for COSMOS API
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready, continuing anyway"
fi

# Clean up previous attempts
rm -f /home/ga/Desktop/aligned_telemetry.json 2>/dev/null || true
rm -f /tmp/async_sensor_fusion_result.json 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/async_sensor_fusion_start_ts

# Query initial received counts securely
get_tlm_count() {
    local target="$1"
    local packet="$2"
    local val
    val=$(cosmos_tlm "$target $packet RECEIVED_COUNT" 2>/dev/null | tr -d ' "\n\r')
    if [[ "$val" =~ ^[0-9]+$ ]]; then
        echo "$val"
    else
        echo "0"
    fi
}

HS_INITIAL=$(get_tlm_count "INST" "HEALTH_STATUS")
ADCS_INITIAL=$(get_tlm_count "INST" "ADCS")

echo "$HS_INITIAL" > /tmp/hs_initial_count
echo "$ADCS_INITIAL" > /tmp/adcs_initial_count

echo "Initial HS Count: $HS_INITIAL"
echo "Initial ADCS Count: $ADCS_INITIAL"

# Ensure Firefox is running
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$OPENC3_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Focus window
if wait_for_window "firefox\|mozilla\|openc3\|cosmos" 30; then
    WID=$(get_firefox_window_id)
    if [ -n "$WID" ]; then
        focus_window "$WID"
        sleep 1
    fi
fi

take_screenshot /tmp/async_sensor_fusion_start.png
echo "=== Setup Complete ==="