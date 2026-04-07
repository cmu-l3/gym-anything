#!/bin/bash
# export_result.sh — OS Polling Baseline Template Optimization
# Captures the final state of the database and exports a JSON result summary.

set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "[export] === Exporting OS Polling Baseline Results ==="

# ------------------------------------------------------------
# 1. Record task end time & screenshot
# ------------------------------------------------------------
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
take_screenshot "/tmp/template_final_screenshot.png" || true

# ------------------------------------------------------------
# 2. Record final state of Device Templates via DB Dump
# ------------------------------------------------------------
echo "[export] Recording final state of Device Templates..."
PG_BIN=$(cat /tmp/opmanager_pg_bin 2>/dev/null || echo "/opt/ManageEngine/OpManager/pgsql/bin/psql")
PG_PORT=$(cat /tmp/opmanager_pg_port 2>/dev/null || echo "13306")
PG_BIN_DIR=$(dirname "$PG_BIN")

FINAL_DUMP_SIZE=0
if [ -f "$PG_BIN_DIR/pg_dump" ]; then
    sudo -u postgres "$PG_BIN_DIR/pg_dump" -p "$PG_PORT" -U postgres -h 127.0.0.1 \
        -t '*template*' -t '*monitor*' --data-only OpManagerDB > /tmp/final_templates.sql 2>/dev/null || true
    
    if [ -f /tmp/final_templates.sql ]; then
        cp /tmp/final_templates.sql /tmp/final_templates_export.sql
        chmod 666 /tmp/final_templates_export.sql
        FINAL_DUMP_SIZE=$(stat -c %s /tmp/final_templates_export.sql 2>/dev/null || echo "0")
        echo "[export] Final DB dump created: $FINAL_DUMP_SIZE bytes."
    fi
fi

INITIAL_DUMP_SIZE=$(stat -c %s /tmp/initial_templates_export.sql 2>/dev/null || echo "0")

# ------------------------------------------------------------
# 3. Create JSON Result
# ------------------------------------------------------------
echo "[export] Assembling result JSON..."

TEMP_JSON=$(mktemp /tmp/template_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_dump_size_bytes": $INITIAL_DUMP_SIZE,
    "final_dump_size_bytes": $FINAL_DUMP_SIZE,
    "db_modified": $(if [ "$INITIAL_DUMP_SIZE" != "$FINAL_DUMP_SIZE" ] && [ "$FINAL_DUMP_SIZE" -gt 0 ]; then echo "true"; else echo "false"; fi),
    "screenshot_path": "/tmp/template_final_screenshot.png"
}
EOF

RESULT_FILE="/tmp/template_optimization_result.json"
rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "[export] Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "[export] === Export Complete ==="