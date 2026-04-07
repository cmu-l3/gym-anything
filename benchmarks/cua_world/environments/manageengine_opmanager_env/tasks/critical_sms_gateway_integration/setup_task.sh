#!/bin/bash
# setup_task.sh — Critical SMS Gateway Integration
# Prepares the environment, clears existing SMS configs, and writes the spec file.

source /workspace/scripts/task_utils.sh

echo "[setup] === Setting up Critical SMS Gateway Integration Task ==="

# ------------------------------------------------------------
# 1. Wait for OpManager to be ready
# ------------------------------------------------------------
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
# 2. Clear existing SMS configurations from DB
# ------------------------------------------------------------
echo "[setup] Clearing existing SMS Gateway configurations..."
PG_BIN=$(cat /tmp/opmanager_pg_bin 2>/dev/null)
PG_PORT=$(cat /tmp/opmanager_pg_port 2>/dev/null || echo "13306")
if [ -n "$PG_BIN" ] && [ -f "$PG_BIN" ]; then
    sudo -u postgres "$PG_BIN" -p "$PG_PORT" -U postgres OpManagerDB -c "DELETE FROM CustomSmsGateway;" 2>/dev/null || true
    sudo -u postgres "$PG_BIN" -p "$PG_PORT" -U postgres OpManagerDB -c "DELETE FROM SmsGateway;" 2>/dev/null || true
    sudo -u postgres "$PG_BIN" -p "$PG_PORT" -U postgres OpManagerDB -c "DELETE FROM NotificationSettings WHERE type='SMS';" 2>/dev/null || true
fi

# ------------------------------------------------------------
# 3. Write SMS API specification file to desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/sms_api_spec.txt" << 'SPEC_EOF'
CRITICAL INFRASTRUCTURE SMS GATEWAY INTEGRATION
================================================
The primary email server is in the same datacenter as our core routers. To ensure the NOC is alerted during a total facility isolation, we must configure an out-of-band SMS gateway using our Twilio account.

Configure the Custom SMS Gateway in OpManager with the following exact parameters:

Provider Name: Twilio-NOC-Alerts
API Endpoint URL: https://api.twilio.com/2010-04-01/Accounts/AC99887766/Messages.json
HTTP Method: POST

HTTP Headers:
Authorization: Basic QUM5OTg4Nzc2NjpkZWZhdWx0X3Rva2Vu

Request Payload (Body):
To=$MobNo&From=+15551234567&Body=$Message

Note: The variables $MobNo and $Message must be used exactly as written so OpManager can inject the dynamic alert data into the payload. Do not substitute them with real numbers.
SPEC_EOF

chown ga:ga "$DESKTOP_DIR/sms_api_spec.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] SMS API Spec written to $DESKTOP_DIR/sms_api_spec.txt"

# ------------------------------------------------------------
# 4. Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/sms_gateway_task_start.txt
date +%s > /tmp/task_start_timestamp
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# 5. Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
echo "[setup] Ensuring Firefox is on OpManager dashboard..."
ensure_firefox_on_opmanager 3 || true

# ------------------------------------------------------------
# 6. Take initial screenshot
# ------------------------------------------------------------
take_screenshot "/tmp/sms_gateway_setup_screenshot.png" || true

echo "[setup] === Critical SMS Gateway Integration Task Setup Complete ==="