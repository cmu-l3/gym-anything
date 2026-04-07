#!/bin/bash
# setup_task.sh — Asset Decommissioning and Retention Workflow
# Prepares the inventory with specific devices and writes the change ticket.

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
# 1. Provision target devices into OpManager
# ------------------------------------------------------------
echo "[setup] Provisioning devices for decommissioning task..."

# List of devices to create (IP:Name)
# We use 127.0.0.x IPs so that OpManager sees them as "Up" immediately.
DEVICES=(
    "127.0.0.11:old-db-server-01"
    "127.0.0.12:old-db-server-02"
    "127.0.0.13:legacy-archive-nas"
    "127.0.0.14:legacy-proxy-01"
    "127.0.0.15:legacy-proxy-02"
    "127.0.0.16:prod-db-server-01"
    "127.0.0.17:prod-proxy-01"
)

for dev in "${DEVICES[@]}"; do
    IP="${dev%%:*}"
    NAME="${dev##*:}"
    
    # Try adding via API first
    opmanager_api_post "/api/json/device/addDevice" "deviceName=${IP}&displayName=${NAME}&type=Server" 2>/dev/null || true
    
    # Fallback to direct DB insert to guarantee they exist for the verifier
    # even if the API is slow/fails
    opmanager_query "INSERT INTO ManagedObject (name, displayname, managed) SELECT '${IP}', '${NAME}', 't' WHERE NOT EXISTS (SELECT 1 FROM ManagedObject WHERE name='${IP}');" 2>/dev/null || true
    
    echo "  Added device: $NAME ($IP)"
done

# ------------------------------------------------------------
# 2. Write the Change Ticket to the desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/CHG-8042_decommission.txt" << 'TICKET_EOF'
ITSM CHANGE TICKET
Ticket Number: CHG-8042
Subject: Decommissioning Phase 4 - Legacy DB and Proxy Assets
Requester: Datacenter Migrations Team

DESCRIPTION:
The physical hardware for Phase 4 has been powered down. We need to update 
OpManager to reflect these retirements to stop alert fatigue, while honoring
our data retention compliance policies.

ACTION ITEMS:

1. COMPLIANCE RETENTION (Do NOT delete these)
These devices require historical metric retention for 3 years.
You must put them in a group named exactly 'Decommissioned-Assets' 
and mark them as 'Unmanaged' to suspend future polling.
   - old-db-server-01
   - old-db-server-02
   - legacy-archive-nas

2. FULLY RETIRED (Delete permanently)
These devices have no retention requirements.
Permanently delete them from the OpManager inventory.
   - legacy-proxy-01
   - legacy-proxy-02

WARNING: All other devices in the OpManager inventory (e.g., prod-db-server-01, 
prod-proxy-01) are actively serving production traffic. They must NOT be unmanaged, 
grouped, or deleted.

END OF TICKET
TICKET_EOF

chown ga:ga "$DESKTOP_DIR/CHG-8042_decommission.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Change ticket written to $DESKTOP_DIR/CHG-8042_decommission.txt"

# ------------------------------------------------------------
# 3. Finalization
# ------------------------------------------------------------
# Record task start timestamp
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/asset_decomm_task_start.txt

# Ensure Firefox is open on OpManager dashboard
ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/asset_decomm_setup_screenshot.png" || true

echo "[setup] asset_decommissioning_and_retention_workflow setup complete."