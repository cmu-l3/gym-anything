#!/bin/bash
# setup_task.sh — Northbound SNMP Trap Forwarding
# Prepares the environment, waits for OpManager, and records the initial state.

source /workspace/scripts/task_utils.sh

echo "[setup] === Setting up Northbound SNMP Trap Forwarding Task ==="

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
# 2. Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/trap_forwarding_task_start.txt
date +%s > /tmp/task_start_timestamp
echo "[setup] Task start time recorded: $(cat /tmp/trap_forwarding_task_start.txt)"

# ------------------------------------------------------------
# 3. Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
echo "[setup] Ensuring Firefox is on OpManager dashboard..."
ensure_firefox_on_opmanager 3 || true

# ------------------------------------------------------------
# 4. Take initial screenshot
# ------------------------------------------------------------
take_screenshot "/tmp/trap_forwarding_setup_screenshot.png" || true

echo "[setup] === Setup Complete ==="
echo ""
echo "Task: Northbound SNMP Trap Forwarding"
echo "  1. Create Device Group: Core-Routers"
echo "  2. Create Notification Profile: Netcool-Trap-Forwarder"
echo "     - Action: Send Trap"
echo "     - Destination: 10.99.99.50"
echo "     - Community: noc-trap-2024"
echo "     - SNMP Version: v2c"
echo "     - Trigger: Critical alarms only"
echo "     - Association: Core-Routers group"
echo ""
echo "OpManager Login: admin / Admin@123"