#!/bin/bash
echo "=== Setting up Empirical Limit Calibration Routine task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start timestamp (crucial for anti-gaming freshness check)
date +%s > /tmp/limit_calibration_start_ts
echo "Task start recorded: $(cat /tmp/limit_calibration_start_ts)"

# Remove stale output files to prevent false positives
rm -f /home/ga/Desktop/limit_calibration_report.json 2>/dev/null || true
rm -f /tmp/limit_calibration_result.json 2>/dev/null || true
mkdir -p /var/lib/app
rm -f /var/lib/app/ground_truth_temp3.csv 2>/dev/null || true

# Wait for COSMOS API to be fully initialized
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready, continuing anyway"
fi

# Query initial limits for TEMP3 to ensure baseline is captured
INITIAL_LIMITS=$(cosmos_api "get_limits" '"INST","HEALTH_STATUS","TEMP3"' | jq -c '.result // []' 2>/dev/null || echo "[]")
echo "Initial TEMP3 Limits: $INITIAL_LIMITS"
echo "$INITIAL_LIMITS" > /tmp/limit_calibration_initial_limits

# Start a hidden background logger to sample the actual telemetry of TEMP3
# This is used to ensure the agent doesn't hallucinate fake "raw_samples"
cat > /tmp/logger.sh << 'EOF'
#!/bin/bash
source /workspace/scripts/task_utils.sh 2>/dev/null || true
echo "timestamp,value" > /var/lib/app/ground_truth_temp3.csv
chmod 644 /var/lib/app/ground_truth_temp3.csv
while true; do
    val=$(cosmos_tlm "INST HEALTH_STATUS TEMP3" 2>/dev/null)
    if [ -n "$val" ] && [ "$val" != "null" ]; then
        echo "$(date +%s),$val" >> /var/lib/app/ground_truth_temp3.csv
    fi
    sleep 2
done
EOF
chmod +x /tmp/logger.sh
/tmp/logger.sh &
echo $! > /tmp/logger_pid

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$OPENC3_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|openc3\|cosmos" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Navigate to COSMOS home
echo "Navigating to COSMOS home..."
navigate_to_url "$OPENC3_URL"
sleep 5

# Focus and maximize the Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/limit_calibration_start.png

echo "=== Empirical Limit Calibration Setup Complete ==="
echo ""
echo "Task: Calibrate TEMP3 limits based on live data and save report."
echo "Output must be written to: /home/ga/Desktop/limit_calibration_report.json"
echo ""