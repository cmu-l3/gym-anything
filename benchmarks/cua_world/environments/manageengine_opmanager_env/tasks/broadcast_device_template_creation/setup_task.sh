#!/bin/bash
# setup_task.sh — Broadcast Device Template Creation
# Waits for OpManager, records start time, writes the spec file, and opens the dashboard.

source /workspace/scripts/task_utils.sh

echo "[setup] === Setting up Broadcast Device Template Task ==="

# ------------------------------------------------------------
# Wait for OpManager to be ready
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
# Write specification file to desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/aoip_template_spec.txt" << 'SPEC_EOF'
BROADCAST IT EQUIPMENT SPECIFICATION
System: AES67/SMPTE-2110 Audio Network
Date: 2024-03-12

The following proprietary broadcast devices must be added to OpManager's 
Device Templates so they are correctly classified during SNMP discovery.

Template 1:
- Device Template Name: Telos-AoIP-xNode
- Vendor Name: TelosAlliance (Create if it does not exist)
- Category: Switch (or Router)
- System OID: .1.3.6.1.4.1.25053.3.1
- Monitoring Interval: 1 minute

Template 2:
- Device Template Name: Lawo-PowerCore
- Vendor Name: Lawo (Create if it does not exist)
- Category: Switch (or Router)
- System OID: .1.3.6.1.4.1.34145.1
- Monitoring Interval: 5 minutes

Please add these exactly as specified in the OpManager Device Templates section.
SPEC_EOF

chown ga:ga "$DESKTOP_DIR/aoip_template_spec.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Specification written to $DESKTOP_DIR/aoip_template_spec.txt"

# ------------------------------------------------------------
# Remove pre-existing templates with these names if they exist (best effort)
# ------------------------------------------------------------
API_KEY=""
if [ -f /tmp/opmanager_api_key ]; then
    API_KEY="$(cat /tmp/opmanager_api_key | tr -d '[:space:]')"
fi

# Basic attempt to clean up using standard DB query directly since we don't know the exact API delete endpoint
if [ -n "$(cat /tmp/opmanager_pg_bin 2>/dev/null)" ]; then
    opmanager_query "DELETE FROM DeviceTemplate WHERE templatename IN ('Telos-AoIP-xNode', 'Lawo-PowerCore');" 2>/dev/null || true
fi

# ------------------------------------------------------------
# Record task start timestamp
# ------------------------------------------------------------
date +%s > /tmp/task_start_timestamp
echo "[setup] Task start time recorded: $(cat /tmp/task_start_timestamp)"

# ------------------------------------------------------------
# Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
echo "[setup] Ensuring Firefox is on OpManager dashboard..."
ensure_firefox_on_opmanager 3 || true

# ------------------------------------------------------------
# Take initial screenshot
# ------------------------------------------------------------
take_screenshot "/tmp/broadcast_template_setup.png" || true

echo "[setup] === Setup Complete ==="