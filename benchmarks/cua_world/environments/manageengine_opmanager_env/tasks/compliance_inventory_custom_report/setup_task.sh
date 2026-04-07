#!/bin/bash
# setup_task.sh — Compliance Inventory Custom Report
# Waits for OpManager, records start state, writes context to desktop, opens dashboard.

source /workspace/scripts/task_utils.sh

echo "[setup] === Setting up Compliance Inventory Custom Report Task ==="

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
# 2. Write SOC 2 context file to desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/SOC2_Audit_Requirements.txt" << 'EOF'
SOC 2 Audit - Evidence Request
================================

The external auditors require a continuous, on-demand report of our monitored infrastructure.

Please configure a Custom Report in OpManager with the following details:
- Report Name: SOC2-Infrastructure-Inventory
- Data Module: Device / Inventory

Required Columns:
1. Device Name (or Display Name)
2. IP Address
3. Vendor
4. Category
5. Uptime (or System Uptime)

Save this report template so the compliance team can export it during the audit phase.
EOF

chown ga:ga "$DESKTOP_DIR/SOC2_Audit_Requirements.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] SOC 2 requirement spec written to desktop."

# ------------------------------------------------------------
# 3. Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/compliance_report_start.txt
date +%s > /tmp/task_start_timestamp
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# 4. Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
echo "[setup] Ensuring Firefox is on OpManager dashboard..."
ensure_firefox_on_opmanager 3 || true

# ------------------------------------------------------------
# 5. Take initial screenshot
# ------------------------------------------------------------
take_screenshot "/tmp/compliance_report_setup.png" || true

echo "[setup] === Task Setup Complete ==="