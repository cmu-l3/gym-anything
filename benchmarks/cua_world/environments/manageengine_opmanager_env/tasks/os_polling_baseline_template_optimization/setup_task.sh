#!/bin/bash
# setup_task.sh — OS Polling Baseline Template Optimization
# Waits for OpManager, records the initial state of the device templates via DB dump,
# and opens Firefox to the dashboard.

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
# 1. Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/template_task_start.txt
date +%s > /tmp/task_start_timestamp
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# 2. Record initial state of Device Templates via DB Dump
# ------------------------------------------------------------
echo "[setup] Recording initial state of Device Templates..."
PG_BIN=$(cat /tmp/opmanager_pg_bin 2>/dev/null || echo "/opt/ManageEngine/OpManager/pgsql/bin/psql")
PG_PORT=$(cat /tmp/opmanager_pg_port 2>/dev/null || echo "13306")
PG_BIN_DIR=$(dirname "$PG_BIN")

if [ -f "$PG_BIN_DIR/pg_dump" ]; then
    # Dump tables related to templates and monitors (schema-agnostic approach)
    sudo -u postgres "$PG_BIN_DIR/pg_dump" -p "$PG_PORT" -U postgres -h 127.0.0.1 \
        -t '*template*' -t '*monitor*' --data-only OpManagerDB > /tmp/initial_templates.sql 2>/dev/null || true
    
    if [ -f /tmp/initial_templates.sql ]; then
        cp /tmp/initial_templates.sql /tmp/initial_templates_export.sql
        chmod 666 /tmp/initial_templates_export.sql
        echo "[setup] Initial DB dump created: $(stat -c %s /tmp/initial_templates_export.sql) bytes."
    else
        echo "[setup] WARNING: Failed to create initial DB dump."
    fi
else
    echo "[setup] WARNING: pg_dump not found at $PG_BIN_DIR/pg_dump"
fi

# ------------------------------------------------------------
# 3. Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
echo "[setup] Ensuring Firefox is on OpManager dashboard..."
ensure_firefox_on_opmanager 3 || true

# ------------------------------------------------------------
# 4. Take initial screenshot
# ------------------------------------------------------------
take_screenshot "/tmp/template_setup_screenshot.png" || true

echo "[setup] === OS Polling Baseline Setup Complete ==="