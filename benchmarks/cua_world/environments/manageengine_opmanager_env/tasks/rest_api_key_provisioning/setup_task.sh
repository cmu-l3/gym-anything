#!/bin/bash
# setup_task.sh — REST API Key Provisioning and Integration Test
# Prepares the environment by ensuring OpManager is running, cleaning up previous artifacts,
# and recording the initial state.

echo "=== Setting up REST API Key Provisioning Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# ------------------------------------------------------------
# 1. Wait for OpManager to be ready
# ------------------------------------------------------------
echo "Waiting for OpManager to be ready..."
WAIT_TIMEOUT=180
ELAPSED=0
until curl -sf -o /dev/null "http://localhost:8060/"; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    if [ "$ELAPSED" -ge "$WAIT_TIMEOUT" ]; then
        echo "WARNING: OpManager not ready after ${WAIT_TIMEOUT}s, continuing anyway." >&2
        break
    fi
done
echo "OpManager is ready."

# ------------------------------------------------------------
# 2. Clean up any existing artifacts
# ------------------------------------------------------------
TARGET_FILE="/home/ga/Desktop/api_integration_test.json"
rm -f "$TARGET_FILE" 2>/dev/null || true
rm -f /tmp/api_key_result.json 2>/dev/null || true

# ------------------------------------------------------------
# 3. Record task start timestamp for anti-gaming
# ------------------------------------------------------------
date +%s > /tmp/task_start_timestamp
echo "Task start time recorded: $(cat /tmp/task_start_timestamp)"

# ------------------------------------------------------------
# 4. Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
echo "Ensuring Firefox is on OpManager dashboard..."
if declare -f ensure_firefox_on_opmanager > /dev/null; then
    ensure_firefox_on_opmanager 3 || true
else
    if ! pgrep -f firefox > /dev/null; then
        su - ga -c "DISPLAY=:1 firefox 'http://localhost:8060' &"
        sleep 5
    fi
    DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# ------------------------------------------------------------
# 5. Take initial screenshot
# ------------------------------------------------------------
sleep 2
if declare -f take_screenshot > /dev/null; then
    take_screenshot "/tmp/api_task_setup_screenshot.png" || true
else
    DISPLAY=:1 scrot "/tmp/api_task_setup_screenshot.png" 2>/dev/null || true
fi

echo "=== REST API Key Provisioning Task Setup Complete ==="
echo "Target File: $TARGET_FILE"
echo "API Endpoint: http://localhost:8060/api/json/device/listDevices"