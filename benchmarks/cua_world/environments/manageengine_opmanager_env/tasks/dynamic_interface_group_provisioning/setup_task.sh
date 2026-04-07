#!/bin/bash
# setup_task.sh — Dynamic Interface Group Provisioning
# Writes the interface group specification document to the desktop.

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
# Remove any pre-existing groups with the target names (best-effort)
# ------------------------------------------------------------
API_KEY=""
if [ -f /tmp/opmanager_api_key ]; then
    API_KEY="$(cat /tmp/opmanager_api_key | tr -d '[:space:]')"
fi

for grp_name in "Enterprise-WAN-Circuits" "Core-Datacenter-Trunks"; do
    GROUP_JSON=$(curl -sf "http://localhost:8060/api/json/group/listGroups?apiKey=${API_KEY}" 2>/dev/null || true)
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
            echo "[setup] Deleted pre-existing group '${grp_name}' (id=${GRP_ID})."
        fi
    fi
done

# ------------------------------------------------------------
# Write the specification document to the desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"
SPEC_FILE="$DESKTOP_DIR/interface_groups_spec.txt"

cat > "$SPEC_FILE" << 'EOF'
Dynamic Interface Group Provisioning Specification
---------------------------------------------------
Date: 2024-03-10
Author: Network Architecture Team

Network operations requires dynamic interface groups for automated bandwidth analytics.
Create two Interface Groups in OpManager (Navigate to Settings > Configuration > Groups, then select Interface Groups).

Group 1
-------
Group Name: Enterprise-WAN-Circuits
Condition: Match ANY of the following (OR logic):
  - Alias contains ISP
  - Interface Name contains Serial

Group 2
-------
Group Name: Core-Datacenter-Trunks
Condition: Match ANY of the following (OR logic):
  - Interface Name contains TenGigabit
  - Interface Name contains FortyGigE

Please ensure the groups are saved successfully in the system.
EOF

chown ga:ga "$SPEC_FILE" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Specification file written to $SPEC_FILE"

# ------------------------------------------------------------
# Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/interface_group_task_start.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/interface_group_setup_screenshot.png" || true

echo "[setup] dynamic_interface_group_provisioning setup complete."