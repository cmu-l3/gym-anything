#!/bin/bash
# setup_task.sh — Custom Script Performance Monitor
# Creates the target script, waits for OpManager, and records the initial state.

source /workspace/scripts/task_utils.sh

echo "[setup] Waiting for OpManager to be ready..."
WAIT_TIMEOUT=120
ELAPSED=0
until curl -sf -o /dev/null "http://localhost:8060/"; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    if [ "$ELAPSED" -ge "$WAIT_TIMEOUT" ]; then
        echo "[setup] ERROR: OpManager not ready after ${WAIT_TIMEOUT}s" >&2
        exit 1
    fi
done
echo "[setup] OpManager is ready."

# ------------------------------------------------------------
# Create the script to be executed by OpManager
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"
SCRIPT_PATH="$DESKTOP_DIR/check_web_connections.sh"

cat > "$SCRIPT_PATH" << 'EOF'
#!/bin/bash
# Returns the count of established TCP connections (simulating active web connections)
ss -ant | grep ESTAB | wc -l
EOF

chmod +x "$SCRIPT_PATH"
chown ga:ga "$SCRIPT_PATH" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Monitoring script written to $SCRIPT_PATH"

# ------------------------------------------------------------
# Remove any pre-existing credentials/templates with spec names (best-effort)
# ------------------------------------------------------------
API_KEY=""
if [ -f /tmp/opmanager_api_key ]; then
    API_KEY="$(cat /tmp/opmanager_api_key | tr -d '[:space:]')"
fi

if [ -n "$API_KEY" ]; then
    # Try to clean up credentials
    CREDS_JSON=$(curl -sf "http://localhost:8060/api/json/admin/getCredentials?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$CREDS_JSON" ]; then
        CRED_ID=$(python3 -c "
import json, sys
try:
    data = json.loads(sys.argv[1])
    creds = data.get('data', [])
    for c in creds:
        if c.get('credentialName') == 'Local-SSH-Service':
            print(c.get('id', ''))
            break
except Exception:
    pass
" "$CREDS_JSON" 2>/dev/null || true)
        if [ -n "$CRED_ID" ]; then
            curl -sf -X POST "http://localhost:8060/api/json/admin/deleteCredential?apiKey=${API_KEY}&credentialId=${CRED_ID}" >/dev/null 2>&1 || true
            echo "[setup] Removed pre-existing credential."
        fi
    fi
fi

# ------------------------------------------------------------
# Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/script_monitor_task_start.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/script_monitor_setup_screenshot.png" || true

echo "[setup] custom_script_performance_monitor setup complete."