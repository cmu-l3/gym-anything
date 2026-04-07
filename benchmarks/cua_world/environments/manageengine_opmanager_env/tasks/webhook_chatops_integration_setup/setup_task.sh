#!/bin/bash
# setup_task.sh — Webhook ChatOps Integration Setup
# Waits for OpManager to be ready, writes the Webhook spec file to the desktop,
# and opens the browser to the dashboard.

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
# Write Webhook API Spec file to desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/webhook_api_specs.txt" << 'SPEC_EOF'
API INTEGRATION SPECIFICATIONS — NOC NOTIFICATIONS
Version: 1.1
Effective Date: 2024-03-15

Instructions: Create three "Invoke WebHook" notification profiles in OpManager
(Settings > Notifications > Notification Profiles). Ensure Profile Names and
Hook URLs match exactly.

========================================================================
INTEGRATION 1: SLACK ALERTS
========================================================================
Profile Name : Slack-NOC-Alerts
Hook URL     : https://hooks.slack.com/services/T9283XYZ/B9912ABC/839201938abcDEF
Method       : POST
Description  : Pushes critical infrastructure alerts directly to the #noc-critical Slack channel.

========================================================================
INTEGRATION 2: JIRA SERVICE DESK TICKETING
========================================================================
Profile Name : Jira-Auto-Ticket
Hook URL     : https://jira.internal.corp/rest/api/2/issue
Method       : POST
Description  : Automatically creates a high-priority incident ticket in Jira for device failures.

========================================================================
INTEGRATION 3: TWILIO ON-CALL SMS PAGING
========================================================================
Profile Name : Twilio-OnCall-SMS
Hook URL     : https://api.twilio.com/2010-04-01/Accounts/AC12345/Messages.json
Method       : POST
Description  : Sends an SMS page to the primary on-call engineer for critical events.
========================================================================

END OF DOCUMENT
SPEC_EOF

chown ga:ga "$DESKTOP_DIR/webhook_api_specs.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Webhook API specifications written to $DESKTOP_DIR/webhook_api_specs.txt"

# ------------------------------------------------------------
# Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/webhook_task_start.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/webhook_setup_screenshot.png" || true

echo "[setup] webhook_chatops_integration_setup setup complete."