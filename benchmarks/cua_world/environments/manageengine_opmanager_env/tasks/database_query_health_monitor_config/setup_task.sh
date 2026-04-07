#!/bin/bash
# setup_task.sh — Database Query Health Monitor Configuration
# Waits for OpManager, records start time, creates the spec file, and opens the dashboard.

source /workspace/scripts/task_utils.sh

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
# Write Database Query Monitoring Spec file to desktop
# ------------------------------------------------------------
DESKTOP_DIR="/home/ga/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/db_query_monitoring_spec.txt" << 'SPEC_EOF'
DATABASE QUERY MONITORING SPECIFICATION
=======================================
Requestor: Lead DBA
Target System: ManageEngine OpManager
Action Required: Create global DB Query Monitor Templates

We need to proactively monitor internal database health beyond basic port checks. 
Please create the following two Database Query Monitors in OpManager:

MONITOR 1 (PostgreSQL Connections)
----------------------------------
Monitor Name: PostgreSQL-Connection-Count
Database Type: PostgreSQL
SQL Query: SELECT count(*) FROM pg_stat_activity;
Unit: Connections

MONITOR 2 (MySQL Transactions)
------------------------------
Monitor Name: MySQL-Transaction-Queue
Database Type: MySQL
SQL Query: SELECT count(*) FROM information_schema.innodb_trx;
Unit: Transactions

Note: You do not need to associate these with any specific devices yet. Just create 
and save the global templates in the DB Query Monitors settings section.
SPEC_EOF

chown ga:ga "$DESKTOP_DIR/db_query_monitoring_spec.txt" 2>/dev/null || true
chown ga:ga "$DESKTOP_DIR" 2>/dev/null || true
echo "[setup] DB query monitoring spec written to $DESKTOP_DIR/db_query_monitoring_spec.txt"

# ------------------------------------------------------------
# Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/db_query_task_start.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
ensure_firefox_on_opmanager || true

# Take an initial screenshot
take_screenshot "/tmp/db_query_setup_screenshot.png" || true

echo "[setup] database_query_health_monitor_config setup complete."