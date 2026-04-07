#!/bin/bash
# setup_task.sh — Legacy Ticketing Email Parser Integration
# Prepares the OpManager environment and places the spec document on the desktop.

source /workspace/scripts/task_utils.sh

echo "[setup] === Setting up Legacy Ticketing Email Parser Integration Task ==="

# ------------------------------------------------------------
# 1. Wait for OpManager to be ready
# ------------------------------------------------------------
echo "[setup] Waiting for OpManager to be ready..."
WAIT_TIMEOUT=120
ELAPSED=0
until curl -sf -o /dev/null "http://localhost:8060/"; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    if [ "$ELAPSED" -ge "$WAIT_TIMEOUT" ]; then
        echo "[setup] ERROR: OpManager not ready after ${WAIT_TIMEOUT}s" >&2
        break
    fi
done
echo "[setup] OpManager is ready."

# ------------------------------------------------------------
# 2. Write the specification file to the desktop as a prop/reference
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/email_parser_spec.txt" << 'SPEC_EOF'
ITSM Integration Specification
------------------------------
Target System: Legacy Ticketing System (LTS-9000)
Integration Method: Email Parsing

Create an Email Notification Profile in OpManager with the following EXACT parameters to ensure tickets are generated correctly:

Profile Name: ITSM-Email-Connector
Trigger Criteria: Critical severity alarms for All Devices
Recipient (To): parser@itsm.internal

Email Subject:
[NOC-ALERT] $severity on $displayName

Email Message Body (must match exactly, including newlines):
Request-Type: Incident
Host: $displayName
IP-Address: $deviceIp
Event-Detail: $alarmMessage
Time-Logged: $strModTime

Note: Use OpManager's built-in variables (the '$' prefixed names above) so they populate dynamically when an alarm triggers.
SPEC_EOF

chown ga:ga "$DESKTOP_DIR/email_parser_spec.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Specification written to $DESKTOP_DIR/email_parser_spec.txt"

# ------------------------------------------------------------
# 3. Record task start timestamp for anti-gaming verification
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_time.txt
date +%s > /tmp/task_start_timestamp
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# 4. Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager || true

# ------------------------------------------------------------
# 5. Take initial screenshot
# ------------------------------------------------------------
take_screenshot "/tmp/task_initial.png" || true

echo "[setup] === Setup complete ==="