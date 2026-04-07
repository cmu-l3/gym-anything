#!/bin/bash
set -e
echo "=== Setting up critical_service_port_monitors task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# 1. Ensure OpManager is running and healthy
# ============================================================
echo "Waiting for OpManager health..."
ensure_opmanager_service 2 || true
wait_for_opmanager_ready 120 || true
ensure_correct_password || true
_fix_password_db_flags || true

# ============================================================
# 2. Record initial service monitor state (anti-gaming baseline)
# ============================================================
echo "Recording initial service monitor state..."

# Discover monitor-related tables
INITIAL_MONITORS=$(opmanager_query "
SELECT tablename FROM pg_tables
WHERE schemaname = 'public'
AND (tablename ILIKE '%monitor%' OR tablename ILIKE '%service%' OR tablename ILIKE '%probe%')
ORDER BY tablename;" 2>/dev/null || echo "")

echo "$INITIAL_MONITORS" > /tmp/initial_monitor_tables.txt

# Store baseline table counts
for table in $INITIAL_MONITORS; do
    if [ -n "$table" ]; then
        TABLE_COUNT=$(opmanager_query "SELECT COUNT(*) FROM \"$table\";" 2>/dev/null || echo "0")
        echo "${table}:${TABLE_COUNT}" >> /tmp/initial_service_monitors.txt
    fi
done

# ============================================================
# 3. Verify target services are running (for realism)
# ============================================================
echo "Verifying target services..."
PG_PORT=$(cat /tmp/opmanager_pg_port 2>/dev/null || echo "13306")
if ss -tlnp 2>/dev/null | grep -q ":${PG_PORT} "; then
    echo "  PostgreSQL listening on port ${PG_PORT} ✓"
fi
if ss -tlnp 2>/dev/null | grep -q ":8060 "; then
    echo "  OpManager web UI listening on port 8060 ✓"
fi
if ss -ulnp 2>/dev/null | grep -q ":161 "; then
    echo "  SNMP agent listening on UDP port 161 ✓"
else
    systemctl restart snmpd 2>/dev/null || true
fi

# ============================================================
# 4. Write the service monitoring directive document
# ============================================================
echo "Creating service monitoring directive..."

DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/service_monitor_directive.txt" << 'DIRECTIVE_EOF'
================================================================================
            INCIDENT POSTMORTEM – SERVICE MONITORING REMEDIATION DIRECTIVE
================================================================================

Document ID:    INC-2024-0847-REMEDIATION
Date Issued:    2024-11-15
Classification: INTERNAL – IT Operations
Author:         NOC Manager – Infrastructure Monitoring Team
Priority:       HIGH – Must be completed before next shift handover

--------------------------------------------------------------------------------
BACKGROUND
--------------------------------------------------------------------------------

On 2024-11-12 at 02:17 UTC, the primary PostgreSQL database service on the
management server (127.0.0.1) became unreachable. Because our OpManager
monitoring configuration only performed ICMP-based device availability checks
(ping), the device continued to report as "UP". No alert was generated until
end users reported application failures 3 hours later.

Root cause analysis identified that we lack TCP port-level service monitors for
all critical infrastructure services hosted on the primary server.

--------------------------------------------------------------------------------
REQUIRED ACTION – CREATE SERVICE MONITORS
--------------------------------------------------------------------------------

The following four (4) TCP/UDP service monitors MUST be created in ManageEngine
OpManager (http://localhost:8060, credentials: admin / Admin@123).

Each monitor must use the EXACT name specified below. Target IP for all monitors
is 127.0.0.1 (the management server itself).

┌─────┬──────────────────────────┬──────────┬───────────┬────────────────────────┐
│  #  │ Monitor Display Name     │ Port     │ Protocol  │ Poll Interval          │
├─────┼──────────────────────────┼──────────┼───────────┼────────────────────────┤
│  1  │ DB-Service-PostgreSQL    │ 13306    │ TCP       │ 3 minutes              │
│  2  │ WebUI-OpManager-Primary  │ 8060     │ TCP       │ 5 minutes              │
│  3  │ SNMP-Agent-Availability  │ 161      │ UDP       │ 5 minutes              │
│  4  │ NTP-Time-Sync-Check      │ 123      │ UDP       │ 10 minutes             │
└─────┴──────────────────────────┴──────────┴───────────┴────────────────────────┘

NOTES:
- Monitor names must match EXACTLY as written (including hyphens and casing).
- All monitors target 127.0.0.1.
- Port 123 is the NTP daemon; it may not currently be running — configure the
  monitor regardless so it will begin reporting once NTP is enabled.
- Navigate to Settings > Monitoring > Service Monitors, or use the Device-level
  Add Monitor workflow.
- Save all monitors and verify they appear in the monitor listing.

================================================================================
DIRECTIVE_EOF

chown ga:ga "$DESKTOP_DIR/service_monitor_directive.txt"
echo "Directive written to $DESKTOP_DIR/service_monitor_directive.txt"

# ============================================================
# 5. Launch Firefox on OpManager dashboard
# ============================================================
echo "Launching Firefox..."

# Kill any existing Firefox
pkill -f firefox 2>/dev/null || true
sleep 2

# Launch Firefox as ga user
su - ga -c "DISPLAY=:1 firefox --no-remote '${OPMANAGER_URL}' &" 2>/dev/null
sleep 5

# Wait for Firefox window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize Firefox
sleep 2
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="