#!/bin/bash
set -e
echo "=== Collecting E-Commerce Audit Results ==="

source /workspace/scripts/task_utils.sh

EXPORT_DIR="/home/ga/Documents/exports"
SCRIPT_DIR="/home/ga/Documents/scripts"
DB_PATH="/home/ga/Documents/databases/ecommerce.db"
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo 0)

take_screenshot /tmp/task_final.png

# --- Check anomaly_report.csv ---
ANOMALY_CSV="$EXPORT_DIR/anomaly_report.csv"
ANOMALY_EXISTS=false
ANOMALY_CREATED_DURING_TASK=false
ANOMALY_SIZE=0
ANOMALY_ROW_COUNT=0
if [ -f "$ANOMALY_CSV" ]; then
    ANOMALY_EXISTS=true
    ANOMALY_SIZE=$(stat -c%s "$ANOMALY_CSV" 2>/dev/null || echo 0)
    FILE_TIME=$(stat -c%Y "$ANOMALY_CSV" 2>/dev/null || echo 0)
    if [ "$FILE_TIME" -gt "$START_TIME" ]; then
        ANOMALY_CREATED_DURING_TASK=true
    fi
    ANOMALY_ROW_COUNT=$(wc -l < "$ANOMALY_CSV" 2>/dev/null || echo 0)
fi

# --- Check audit_summary.csv ---
SUMMARY_CSV="$EXPORT_DIR/audit_summary.csv"
SUMMARY_EXISTS=false
SUMMARY_CREATED_DURING_TASK=false
SUMMARY_SIZE=0
SUMMARY_ROW_COUNT=0
if [ -f "$SUMMARY_CSV" ]; then
    SUMMARY_EXISTS=true
    SUMMARY_SIZE=$(stat -c%s "$SUMMARY_CSV" 2>/dev/null || echo 0)
    FILE_TIME=$(stat -c%Y "$SUMMARY_CSV" 2>/dev/null || echo 0)
    if [ "$FILE_TIME" -gt "$START_TIME" ]; then
        SUMMARY_CREATED_DURING_TASK=true
    fi
    SUMMARY_ROW_COUNT=$(wc -l < "$SUMMARY_CSV" 2>/dev/null || echo 0)
fi

# --- Check audit_queries.sql ---
SCRIPT_FILE="$SCRIPT_DIR/audit_queries.sql"
SCRIPT_EXISTS=false
SCRIPT_SIZE=0
if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS=true
    SCRIPT_SIZE=$(stat -c%s "$SCRIPT_FILE" 2>/dev/null || echo 0)
fi

# --- Check DBeaver connection ---
CONN_FOUND=false
if [ -f "$DBEAVER_CONFIG" ]; then
    if grep -qi "EcommerceAudit" "$DBEAVER_CONFIG" 2>/dev/null; then
        CONN_FOUND=true
    fi
fi

# --- Check DBeaver running ---
APP_RUNNING=false
if pgrep -f "dbeaver" > /dev/null 2>&1; then
    APP_RUNNING=true
fi

# --- Check ground truth exists ---
GT_EXISTS=false
if [ -f /tmp/audit_ground_truth.json ]; then
    GT_EXISTS=true
fi

# --- Write result JSON ---
TEMP=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP" << ENDJSON
{
    "task_start": $START_TIME,
    "anomaly_report": {
        "exists": $ANOMALY_EXISTS,
        "created_during_task": $ANOMALY_CREATED_DURING_TASK,
        "size_bytes": $ANOMALY_SIZE,
        "row_count": $ANOMALY_ROW_COUNT,
        "path": "$ANOMALY_CSV"
    },
    "audit_summary": {
        "exists": $SUMMARY_EXISTS,
        "created_during_task": $SUMMARY_CREATED_DURING_TASK,
        "size_bytes": $SUMMARY_SIZE,
        "row_count": $SUMMARY_ROW_COUNT,
        "path": "$SUMMARY_CSV"
    },
    "sql_script": {
        "exists": $SCRIPT_EXISTS,
        "size_bytes": $SCRIPT_SIZE,
        "path": "$SCRIPT_FILE"
    },
    "dbeaver_connection_found": $CONN_FOUND,
    "app_running": $APP_RUNNING,
    "ground_truth_exists": $GT_EXISTS,
    "ground_truth_path": "/tmp/audit_ground_truth.json"
}
ENDJSON

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP"

echo "=== Results collected ==="
