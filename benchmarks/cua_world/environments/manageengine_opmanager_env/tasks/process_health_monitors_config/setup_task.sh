#!/bin/bash
# setup_task.sh — Process Health Monitors Config
# Prepares the environment, creates requirements doc, ensures processes are running,
# and captures the initial database state for anti-gaming.

source /workspace/scripts/task_utils.sh

echo "[setup] === Setting up Process Health Monitors Task ==="

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
# 2. Ensure target processes are running
# ------------------------------------------------------------
echo "[setup] Ensuring all target processes are running locally..."

# sshd
if ! pgrep -f "sshd" > /dev/null; then
    systemctl start ssh 2>/dev/null || service ssh start 2>/dev/null || /etc/init.d/ssh start 2>/dev/null || true
fi

# cron
if ! pgrep -f "cron" > /dev/null; then
    systemctl start cron 2>/dev/null || service cron start 2>/dev/null || /etc/init.d/cron start 2>/dev/null || true
fi

# ------------------------------------------------------------
# 3. Write requirements document to Desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/process_monitoring_requirements.txt" << 'REQ_EOF'
=================================================================
  INFRASTRUCTURE PROCESS MONITORING REQUIREMENTS
  Document: PROC-MON-2024-Q4  |  Classification: Internal
  Prepared by: Systems Engineering  |  Date: 2024-11-15
=================================================================

COMPLIANCE REFERENCE: SOC-2 CC7.2, CIS Benchmark v8 Control 4.8

SERVER SCOPE:
  Target Host: 127.0.0.1 (OpManager infrastructure server)
  Monitoring Platform: ManageEngine OpManager
  SNMP Community: public (read-only)

REQUIRED PROCESS MONITORS:
  Each process below MUST have an individual monitor configured
  in OpManager on the target device. Monitor names must use the
  exact process name as listed.

  1. postgres
     Role: PostgreSQL database engine (OpManager data store)
     Criticality: CRITICAL

  2. java
     Role: OpManager application server (JVM runtime)
     Criticality: CRITICAL

  3. snmpd
     Role: SNMP monitoring agent (Net-SNMP daemon)
     Criticality: HIGH

  4. cron
     Role: System task scheduler (periodic job execution)
     Criticality: MEDIUM

  5. sshd
     Role: Secure Shell daemon (remote administration access)
     Criticality: HIGH

IMPLEMENTATION DEADLINE: End of current maintenance window
SIGN-OFF REQUIRED: NOC Manager
=================================================================
REQ_EOF

chown ga:ga "$DESKTOP_DIR/process_monitoring_requirements.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] Requirements document written."

# ------------------------------------------------------------
# 4. Capture Initial Database State (Anti-Gaming)
# ------------------------------------------------------------
echo "[setup] Capturing initial DB state for process monitors..."

# Look for process monitor tables
PROC_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%process%' OR tablename ILIKE '%monitor%' OR tablename ILIKE '%resource%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

TMP_INIT_DB="/tmp/initial_process_db.txt"
> "$TMP_INIT_DB"

for tbl in $PROC_TABLES; do
    echo "=== TABLE: $tbl ===" >> "$TMP_INIT_DB"
    opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 500;" 2>/dev/null >> "$TMP_INIT_DB" || true
done

echo "[setup] Initial DB state captured."

# ------------------------------------------------------------
# 5. Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_timestamp.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# 6. Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/process_monitors_setup_screenshot.png" || true

echo "[setup] === Process Health Monitors Setup Complete ==="