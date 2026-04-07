#!/bin/bash
# setup_task.sh — Scheduled Performance Reporting
# Prepares the environment for the scheduled_performance_reporting task.
# Waits for OpManager, records start state, opens Firefox on the dashboard.


source /workspace/scripts/task_utils.sh

echo "[setup] === Setting up Scheduled Performance Reporting Task ==="

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
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/reporting_task_start.txt
date +%s > /tmp/task_start_timestamp
echo "[setup] Task start time recorded: $(cat /tmp/reporting_task_start.txt)"

# ------------------------------------------------------------
# 3. Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
echo "[setup] Ensuring Firefox is on OpManager dashboard..."
ensure_firefox_on_opmanager 3 || true

# ------------------------------------------------------------
# 4. Take initial screenshot
# ------------------------------------------------------------
take_screenshot "/tmp/reporting_setup_screenshot.png" || true

echo "[setup] === Scheduled Performance Reporting Task Setup Complete ==="
echo ""
echo "Task: Create and schedule two reports in OpManager"
echo ""
echo "  Report 1: Infrastructure-Availability-Report"
echo "    Type: Availability"
echo "    Devices: All"
echo "    Schedule: Weekly, every Monday at 08:00 AM"
echo "    Email: it-ops@company.internal"
echo ""
echo "  Report 2: Executive-Performance-Summary"
echo "    Type: Performance"
echo "    Devices: All"
echo "    Schedule: Monthly, 1st of each month at 07:00 AM"
echo "    Email: it-executive@company.internal"
echo ""
echo "OpManager Login: admin / Admin@123"
echo "OpManager URL: http://localhost:8060"
echo "Navigate to: Reports > Schedule Reports (or Reports > Add Report)"
echo ""
