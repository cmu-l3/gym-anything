#!/bin/bash
# setup_task.sh — Device Inventory Reconciliation
# Prepares OpManager by seeding an 'UNKNOWN-DEVICE-01' and placing the asset register on the desktop.

source /workspace/scripts/task_utils.sh

echo "[setup] === Setting up Device Inventory Reconciliation Task ==="

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
# 2. Modify existing 127.0.0.1 device to be 'UNKNOWN-DEVICE-01'
# ------------------------------------------------------------
echo "[setup] Seeding mislabeled device in database..."
# Use database queries to forcibly rename the localhost device if it exists
opmanager_query "UPDATE managedobject SET displayname='UNKNOWN-DEVICE-01', name='UNKNOWN-DEVICE-01' WHERE ipaddress='127.0.0.1';" 2>/dev/null || true
opmanager_query "UPDATE toponode SET displayname='UNKNOWN-DEVICE-01', name='UNKNOWN-DEVICE-01' WHERE ipaddress='127.0.0.1';" 2>/dev/null || true
# Clear any existing location or contact data for it
opmanager_query "UPDATE systeminfo SET syslocation='', syscontact='' WHERE nodeid IN (SELECT nodeid FROM toponode WHERE ipaddress='127.0.0.1');" 2>/dev/null || true

# Delete any existing devices with the new IPs to ensure a clean state
opmanager_query "DELETE FROM managedobject WHERE ipaddress IN ('10.255.0.2', '10.255.0.3');" 2>/dev/null || true

# ------------------------------------------------------------
# 3. Write the asset register document to the desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"
REGISTER_FILE="$DESKTOP_DIR/asset_register_q4.txt"

cat > "$REGISTER_FILE" << 'EOF'
═══════════════════════════════════════════════════════════════
  INFRASTRUCTURE ASSET REGISTER — Q4 RECONCILIATION
  Issued by: IT Asset Management Office
  Date: 2024-12-01
  Classification: Internal
═══════════════════════════════════════════════════════════════

All entries below represent the AUTHORITATIVE record for each
infrastructure device. OpManager inventory MUST match these
values exactly. Discrepancies must be corrected immediately.

───────────────────────────────────────────────────────────────
DEVICE 1 — Core Distribution Switch
───────────────────────────────────────────────────────────────
  Display Name .... Core-Switch-HQ-01
  IP Address ...... 127.0.0.1
  Device Type ..... Switch
  Location ........ HQ Building A, Floor 3, Rack R12
  Contact ......... Jane Chen (jchen@infraops.local)
  Status .......... Active — currently monitored as
                    "UNKNOWN-DEVICE-01" (MUST be renamed)

───────────────────────────────────────────────────────────────
DEVICE 2 — Production Application Server
───────────────────────────────────────────────────────────────
  Display Name .... App-Server-Prod-01
  IP Address ...... 10.255.0.2
  Device Type ..... Server
  Location ........ DC-East, Row 4, Rack E07
  Contact ......... Mike Torres (mtorres@infraops.local)
  Status .......... Deployed 2024-11-15 — NOT YET in OpManager

───────────────────────────────────────────────────────────────
DEVICE 3 — DMZ Perimeter Firewall
───────────────────────────────────────────────────────────────
  Display Name .... Perimeter-FW-DMZ-01
  IP Address ...... 10.255.0.3
  Device Type ..... Firewall
  Location ........ DC-East, Row 1, Rack E01
  Contact ......... Sarah Kim (skim@infraops.local)
  Status .......... Deployed 2024-11-22 — NOT YET in OpManager

═══════════════════════════════════════════════════════════════
  END OF REGISTER — 3 devices total
  Next review: 2025-03-01
═══════════════════════════════════════════════════════════════
EOF

chown ga:ga "$REGISTER_FILE" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Asset register written to $REGISTER_FILE"

# ------------------------------------------------------------
# 4. Record task start timestamp and initial state
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/inventory_task_start.txt
date +%s > /tmp/task_start_timestamp

# Record initial device count for anti-gaming verification
INITIAL_COUNT=$(opmanager_query "SELECT count(*) FROM managedobject WHERE type='Node';" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_device_count
echo "[setup] Task start time recorded. Initial device count: $INITIAL_COUNT"

# ------------------------------------------------------------
# 5. Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
echo "[setup] Ensuring Firefox is on OpManager dashboard..."
ensure_firefox_on_opmanager 3 || true

# Take an initial screenshot
take_screenshot "/tmp/inventory_setup_screenshot.png" || true

echo "[setup] === Device Inventory Reconciliation Task Setup Complete ==="