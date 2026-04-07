#!/bin/bash
# setup_task.sh — SIEM Syslog Forwarding Profile Configuration
# Writes the SIEM integration specification to the desktop and waits for OpManager.

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
# Remove any pre-existing profiles with the spec name
# ------------------------------------------------------------
API_KEY=""
if [ -f /tmp/opmanager_api_key ]; then
    API_KEY="$(cat /tmp/opmanager_api_key | tr -d '[:space:]')"
fi

if [ -n "$API_KEY" ]; then
    NOTIF_JSON=$(curl -sf "http://localhost:8060/api/json/notification/listNotificationProfiles?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$NOTIF_JSON" ]; then
        PROFILE_ID=$(python3 -c "
import json, sys
try:
    data = json.loads(sys.argv[1])
    profiles = data if isinstance(data, list) else data.get('data', data.get('notificationProfiles', []))
    for p in profiles:
        if isinstance(p, dict) and p.get('profileName','') == 'SOC-SIEM-Forwarder':
            print(p.get('profileId', p.get('id', '')))
            break
except Exception:
    pass
" "$NOTIF_JSON" 2>/dev/null || true)
        
        if [ -n "$PROFILE_ID" ]; then
            curl -sf -X POST "http://localhost:8060/api/json/notification/deleteNotificationProfile?apiKey=${API_KEY}&profileId=${PROFILE_ID}" -o /dev/null 2>/dev/null || true
            echo "[setup] Deleted pre-existing profile 'SOC-SIEM-Forwarder' (id=${PROFILE_ID})."
        fi
    fi
fi

# ------------------------------------------------------------
# Write SIEM specification file to desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/siem_forwarding_spec.txt" << 'SPEC_EOF'
SIEM Integration Specification
Document ID: SEC-SIEM-001
Effective Date: 2024-04-15

REQUIREMENT:
Configure ManageEngine OpManager to forward all critical infrastructure alarms to the SOC's central SIEM via Syslog.

CONFIGURATION DETAILS:
- Profile Type: Syslog Profile (in Settings > Notifications > Notification Profiles)
- Profile Name: SOC-SIEM-Forwarder
- Destination Host / IP: 10.50.100.10
- Destination Port: 514
- Syslog Facility: Local 7 (or local7)

ALARM CRITERIA:
- Select ONLY "Critical" and "Trouble" severities.
- Apply to all devices/infrastructure.

PAYLOAD / MESSAGE FORMAT:
Customize the syslog message exactly as follows (using available OpManager variables):
OpManagerAlert | $displayName | $stringSeverity | $message

END OF SPECIFICATION
SPEC_EOF

chown ga:ga "$DESKTOP_DIR/siem_forwarding_spec.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] SIEM specification written to $DESKTOP_DIR/siem_forwarding_spec.txt"

# ------------------------------------------------------------
# Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/siem_syslog_task_start.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/siem_syslog_setup_screenshot.png" || true

echo "[setup] siem_syslog_forwarding_profile_config setup complete."