#!/bin/bash
echo "=== Setting up Command Throughput Benchmarking task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready, continuing anyway"
fi

# Clean up any stale files from previous runs
rm -f /home/ga/Desktop/throughput_benchmark.json 2>/dev/null || true
rm -f /tmp/throughput_benchmark_result.json 2>/dev/null || true

# Record task start timestamp to prevent gaming (must be done after cleanup)
date +%s > /tmp/throughput_benchmark_start_ts
echo "Task start recorded: $(cat /tmp/throughput_benchmark_start_ts)"

# Record initial COLLECT command count from the backend API
INITIAL_CMD_COUNT=$(cosmos_api "get_cmd_cnt" '"INST","COLLECT"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")
echo "Initial COLLECT command count: $INITIAL_CMD_COUNT"
printf '%s' "$INITIAL_CMD_COUNT" > /tmp/throughput_benchmark_initial_cmd_count

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
take_screenshot /tmp/throughput_benchmark_start.png

echo "=== Setup Complete ==="
echo ""
echo "Task: Benchmark COSMOS API uplink throughput with 50 COLLECT commands."
echo "Output must be written to: /home/ga/Desktop/throughput_benchmark.json"
echo ""