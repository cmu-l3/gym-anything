#!/bin/bash
# setup_task.sh — Custom SNMP Monitor Configuration
# Prepares the environment, writes the specification document, and opens the dashboard.

source /workspace/scripts/task_utils.sh

echo "[setup] === Setting up Custom SNMP Monitor Task ==="

# 1. Wait for OpManager to be ready
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

# 2. Clean up any existing monitors with these names (best-effort)
API_KEY=""
if [ -f /tmp/opmanager_api_key ]; then
    API_KEY="$(cat /tmp/opmanager_api_key | tr -d '[:space:]')"
fi

# 3. Write the specification document to the Desktop
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/custom_monitor_spec.txt" << 'SPEC_EOF'
====================================================================
  INFRASTRUCTURE MONITORING EXTENSION SPECIFICATION
  Version: 3.1 — Capacity Planning Team
  Date: 2024-11-15
  Target Platform: ManageEngine OpManager
====================================================================

BACKGROUND:
The default OpManager monitoring templates do not provide granular
visibility into per-interval load averages, active TCP session
counts, or swap memory allocation. The following custom SNMP
monitors must be added to all Linux infrastructure hosts, starting
with the OpManager server itself (127.0.0.1).

All monitors use SNMP v2c with community string: public

====================================================================
MONITOR 1: System-Load-1min
--------------------------------------------------------------------
  Display Name : System-Load-1min
  Target Device: 127.0.0.1
  SNMP OID     : 1.3.6.1.4.1.2021.10.1.3.1
  Description  : 1-minute system load average (UCD-SNMP-MIB::laLoad.1)
  Data Type    : String (floating point value)
  Poll Interval: Default
====================================================================

====================================================================
MONITOR 2: System-Load-5min
--------------------------------------------------------------------
  Display Name : System-Load-5min
  Target Device: 127.0.0.1
  SNMP OID     : 1.3.6.1.4.1.2021.10.1.3.2
  Description  : 5-minute system load average (UCD-SNMP-MIB::laLoad.2)
  Data Type    : String (floating point value)
  Poll Interval: Default
====================================================================

====================================================================
MONITOR 3: TCP-ActiveConnections
--------------------------------------------------------------------
  Display Name : TCP-ActiveConnections
  Target Device: 127.0.0.1
  SNMP OID     : 1.3.6.1.2.1.6.9.0
  Description  : Number of currently established TCP connections
                 (TCP-MIB::tcpCurrEstab.0)
  Data Type    : Integer (gauge)
  Poll Interval: Default
====================================================================

====================================================================
MONITOR 4: Swap-Total-Size
--------------------------------------------------------------------
  Display Name : Swap-Total-Size
  Target Device: 127.0.0.1
  SNMP OID     : 1.3.6.1.4.1.2021.4.3.0
  Description  : Total swap space in kilobytes
                 (UCD-SNMP-MIB::memTotalSwap.0)
  Data Type    : Integer (kilobytes)
  Poll Interval: Default
====================================================================

VERIFICATION:
After creating all monitors, confirm each is active and returning
data by checking the monitor list in OpManager's web interface.

END OF SPECIFICATION
SPEC_EOF

chown ga:ga "$DESKTOP_DIR/custom_monitor_spec.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Specification written to $DESKTOP_DIR/custom_monitor_spec.txt"

# 4. Record task start timestamp and baseline
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_time.txt
date +%s > /tmp/task_start_timestamp

# Try to get baseline custom monitor count from DB
BASELINE_COUNT=$(opmanager_query "SELECT COUNT(*) FROM pg_tables WHERE schemaname='public' AND tablename ILIKE '%polleddata%';" 2>/dev/null | tr -d ' ' || echo "0")
echo "$BASELINE_COUNT" > /tmp/initial_monitor_count.txt
echo "[setup] Task start time recorded."

# 5. Ensure Firefox is open on OpManager dashboard
ensure_firefox_on_opmanager 3 || true

# Take an initial screenshot
take_screenshot "/tmp/custom_monitor_setup_screenshot.png" || true

echo "[setup] === Setup Complete ==="