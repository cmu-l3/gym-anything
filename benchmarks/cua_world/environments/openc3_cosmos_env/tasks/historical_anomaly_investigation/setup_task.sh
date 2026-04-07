#!/bin/bash
echo "=== Setting up Historical Anomaly Investigation task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready, continuing anyway"
fi

# Clean up any stale files
rm -f /home/ga/Desktop/anomaly_window.json 2>/dev/null || true
rm -f /home/ga/Desktop/anomaly_investigation.json 2>/dev/null || true
rm -f /tmp/historical_anomaly_investigation_result.json 2>/dev/null || true

# Record task start timestamp
date +%s > /tmp/historical_anomaly_investigation_start_ts

# ==============================================================================
# INJECT RANDOM ANOMALY & ESTABLISH GROUND TRUTH
# ==============================================================================
echo "Generating random thermal anomaly..."

# Create secure directory for ground truth
mkdir -p /var/lib/app/ground_truth
chmod 700 /var/lib/app/ground_truth

# Generate random parameters
SAMPLES=$(( 12 + RANDOM % 7 )) # Random duration between 12 and 18 samples
PEAK_TEMP=$(awk -v min=160.00 -v max=175.00 'BEGIN{srand(); printf "%.2f", min+rand()*(max-min)}')

echo "Truth: Peak $PEAK_TEMP for $SAMPLES samples"

# Save ground truth securely
cat > /var/lib/app/ground_truth/anomaly_truth.json << EOF
{
  "peak_temperature": $PEAK_TEMP,
  "samples_above_threshold": $SAMPLES
}
EOF
chmod 600 /var/lib/app/ground_truth/anomaly_truth.json

# Record start of the anomaly window (pad by 5 seconds)
WINDOW_START=$(date -u -d "5 seconds ago" +"%Y-%m-%dT%H:%M:%SZ")

# Inject the anomaly into the live COSMOS telemetry stream
for ((i=1; i<=SAMPLES; i++)); do
    cosmos_api "inject_tlm" '"INST","HEALTH_STATUS",{"TEMP1":'$PEAK_TEMP'}' > /dev/null
    sleep 1
done

# Wait slightly and record end of anomaly window (pad by 5 seconds)
sleep 5
WINDOW_END=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Provide the window and instructions to the agent
cat > /home/ga/Desktop/anomaly_window.json << EOF
{
  "investigation_target": "INST HEALTH_STATUS TEMP1",
  "window_start": "$WINDOW_START",
  "window_end": "$WINDOW_END",
  "threshold": 150.0,
  "instructions": "Extract historical telemetry for the specified target and time window. Find the peak temperature and count the exact number of telemetry samples strictly greater than the threshold."
}
EOF
chown ga:ga /home/ga/Desktop/anomaly_window.json

# ==============================================================================
# SETUP UI
# ==============================================================================
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$OPENC3_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

if ! wait_for_window "firefox\|mozilla\|openc3\|cosmos" 30; then
    echo "WARNING: Firefox window not detected"
fi

echo "Navigating to COSMOS home..."
navigate_to_url "$OPENC3_URL"
sleep 5

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    sleep 1
fi

take_screenshot /tmp/historical_anomaly_investigation_start.png

echo "=== Setup Complete ==="
echo "Anomaly injected and logged. Agent parameters written to Desktop."