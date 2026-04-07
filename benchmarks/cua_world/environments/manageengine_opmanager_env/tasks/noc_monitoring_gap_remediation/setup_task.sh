#!/bin/bash
# setup_task.sh — NOC Monitoring Gap Remediation
# Creates contamination state and writes the NOC spec file to the desktop.


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
# Remove any pre-existing groups with the spec-correct names
# (best-effort; ignore errors if they don't exist)
# ------------------------------------------------------------
API_KEY=""
if [ -f /tmp/opmanager_api_key ]; then
    API_KEY="$(cat /tmp/opmanager_api_key | tr -d '[:space:]')"
fi

for grp_name in "Core-Network-Infrastructure" "Production-Application-Servers" "DMZ-Security-Perimeter" "Core-Network" "Production-Servers"; do
    # Attempt to look up the group ID then delete it; ignore all errors
    GROUP_JSON=$(curl -sf \
        "http://localhost:8060/api/json/group/listGroups?apiKey=${API_KEY}" \
        2>/dev/null || true)
    if [ -n "$GROUP_JSON" ]; then
        GRP_ID=$(python3 -c "
import json, sys
try:
    data = json.loads(sys.argv[1])
    groups = data if isinstance(data, list) else data.get('data', data.get('groups', []))
    for g in groups:
        if isinstance(g, dict) and g.get('displayName','') == sys.argv[2]:
            print(g.get('groupId', g.get('id', '')))
            break
except Exception:
    pass
" "$GROUP_JSON" "$grp_name" 2>/dev/null || true)
        if [ -n "$GRP_ID" ]; then
            curl -sf -X POST \
                "http://localhost:8060/api/json/group/deleteGroup?apiKey=${API_KEY}&groupId=${GRP_ID}" \
                -o /dev/null 2>/dev/null || true
            echo "[setup] Deleted existing group '${grp_name}' (id=${GRP_ID})."
        fi
    fi
done

# ------------------------------------------------------------
# Create contamination groups (wrong names — agent must fix)
# ------------------------------------------------------------
echo "[setup] Creating contamination groups..."
opmanager_api_post "/api/json/group/addGroup" \
    "groupName=Core-Network&description=Core+network+devices" \
    2>/dev/null || true
opmanager_api_post "/api/json/group/addGroup" \
    "groupName=Production-Servers&description=Production+servers" \
    2>/dev/null || true
echo "[setup] Contamination groups created."

# ------------------------------------------------------------
# Write NOC monitoring spec file to desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/noc_monitoring_spec.txt" << 'SPEC_EOF'
NOC Infrastructure Monitoring Requirements Specification
Version: 2.3
Effective Date: 2024-03-01
Authorized By: Head of Network Operations

SECTION 1: REQUIRED DEVICE GROUPS
-----------------------------------
All device groups must be created in OpManager with exact names as listed.

Group 1:
  Name: Core-Network-Infrastructure
  Description: Core routers, switches, and network backbone devices

Group 2:
  Name: Production-Application-Servers
  Description: Production application and web servers

Group 3:
  Name: DMZ-Security-Perimeter
  Description: DMZ firewalls, load balancers, and security appliances

SECTION 2: REQUIRED URL MONITORS
----------------------------------
The following HTTP service endpoints must be monitored:

Monitor 1:
  Display Name: OpManager-Self-Monitor
  URL: http://localhost:8060
  Poll Interval (minutes): 5
  Timeout (seconds): 10

Monitor 2:
  Display Name: SNMP-Gateway-Check
  URL: http://localhost:8060/api/json/device/listDevices
  Poll Interval (minutes): 10
  Timeout (seconds): 30

SECTION 3: REQUIRED NOTIFICATION PROFILES
-------------------------------------------

Profile 1:
  Name: NOC-24x7-Critical-Alert
  Email Recipient: noc-oncall@company.internal
  Trigger: Device Down, Critical Threshold Violation

END OF SPECIFICATION
SPEC_EOF

chown ga:ga "$DESKTOP_DIR/noc_monitoring_spec.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Spec file written to $DESKTOP_DIR/noc_monitoring_spec.txt"

# ------------------------------------------------------------
# Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/noc_monitoring_task_start.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/noc_monitoring_setup_screenshot.png" || true

echo "[setup] noc_monitoring_gap_remediation setup complete."
