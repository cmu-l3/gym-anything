#!/bin/bash
# setup_task.sh — Infrastructure Health Assessment Report
# Waits for OpManager, ensures localhost is discovered, and opens Firefox.

source /workspace/scripts/task_utils.sh

echo "[setup] Waiting for OpManager to be ready..."
WAIT_TIMEOUT=180
ELAPSED=0
until curl -sf -o /dev/null "http://localhost:8060/"; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    if [ "$ELAPSED" -ge "$WAIT_TIMEOUT" ]; then
        echo "[setup] WARNING: OpManager not ready after ${WAIT_TIMEOUT}s, continuing anyway." >&2
        break
    fi
done
echo "[setup] OpManager is ready."

# ------------------------------------------------------------
# Ensure Desktop directory exists
# ------------------------------------------------------------
mkdir -p /home/ga/Desktop
chown -R ga:ga /home/ga/Desktop

# ------------------------------------------------------------
# Obtain API key
# ------------------------------------------------------------
API_KEY=""
if [ -f /tmp/opmanager_api_key ]; then
    API_KEY="$(cat /tmp/opmanager_api_key | tr -d '[:space:]')"
fi
if [ -z "$API_KEY" ]; then
    LOGIN_RESP=$(curl -sf -X POST \
        "http://localhost:8060/apiv2/login" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=admin&password=Admin%40123" 2>/dev/null || true)
    if [ -n "$LOGIN_RESP" ]; then
        API_KEY=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    print(d.get('apiKey', d.get('data', {}).get('apiKey', '')))
except Exception:
    pass
" "$LOGIN_RESP" 2>/dev/null || true)
    fi
fi

# ------------------------------------------------------------
# Ensure 127.0.0.1 is monitored
# ------------------------------------------------------------
echo "[setup] Ensuring localhost (127.0.0.1) is discovered..."
if [ -n "$API_KEY" ]; then
    # Fire a discovery request just in case it isn't automatically discovered
    curl -sf -X POST "http://localhost:8060/api/json/discovery/addDevice?apiKey=${API_KEY}" \
        -d "deviceName=127.0.0.1&netMask=255.255.255.0" > /dev/null 2>&1 || true
    # Wait a moment for OpManager to process and poll
    sleep 10
else
    echo "[setup] WARNING: Could not get API key to trigger discovery."
fi

# ------------------------------------------------------------
# Record task start timestamp
# ------------------------------------------------------------
date +%s > /tmp/task_start_time.txt
echo "[setup] Task start time recorded: $(cat /tmp/task_start_time.txt)"

# ------------------------------------------------------------
# Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
echo "[setup] Ensuring Firefox is on OpManager dashboard..."
ensure_firefox_on_opmanager 3 || true

# ------------------------------------------------------------
# Take initial screenshot
# ------------------------------------------------------------
take_screenshot "/tmp/health_assessment_setup.png" || true

echo "[setup] === Health Assessment Report Task Setup Complete ==="