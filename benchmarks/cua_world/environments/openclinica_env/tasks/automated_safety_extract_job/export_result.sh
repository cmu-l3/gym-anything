#!/bin/bash
echo "=== Exporting automated_safety_extract_job result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Query for Dataset
DATASET_DATA=$(oc_query "SELECT dataset_id, name FROM dataset WHERE LOWER(name) = 'idmc_weekly_safety' ORDER BY dataset_id DESC LIMIT 1" 2>/dev/null || echo "")

DATASET_EXISTS="false"
DATASET_ID=""
DATASET_NAME=""
ITEM_COUNT="0"

if [ -n "$DATASET_DATA" ]; then
    DATASET_EXISTS="true"
    DATASET_ID=$(echo "$DATASET_DATA" | cut -d'|' -f1)
    DATASET_NAME=$(echo "$DATASET_DATA" | cut -d'|' -f2)
    ITEM_COUNT=$(oc_query "SELECT COUNT(*) FROM dataset_item_status WHERE dataset_id = $DATASET_ID" 2>/dev/null || echo "0")
fi

echo "Dataset Exists: $DATASET_EXISTS, ID: $DATASET_ID, Name: $DATASET_NAME, Items: $ITEM_COUNT"

# Query for Quartz Job
JOB_DATA=$(oc_query "SELECT job_name, description FROM qrtz_job_details WHERE LOWER(job_name) LIKE '%idmc_monday_extract%' ORDER BY job_name DESC LIMIT 1" 2>/dev/null || echo "")

JOB_EXISTS="false"
JOB_NAME=""
JOB_DESC=""
CRON_EXPR=""

if [ -n "$JOB_DATA" ]; then
    JOB_EXISTS="true"
    JOB_NAME=$(echo "$JOB_DATA" | cut -d'|' -f1)
    JOB_DESC=$(echo "$JOB_DATA" | cut -d'|' -f2)
    CRON_EXPR=$(oc_query "SELECT ct.cron_expression FROM qrtz_cron_triggers ct JOIN qrtz_triggers t ON ct.trigger_name = t.trigger_name WHERE t.job_name = '$JOB_NAME' LIMIT 1" 2>/dev/null || echo "")
fi

echo "Job Exists: $JOB_EXISTS, Name: $JOB_NAME, Cron: $CRON_EXPR"

# Audit Log
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")

# Write output
TEMP_JSON=$(mktemp /tmp/safety_extract_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "dataset_exists": $DATASET_EXISTS,
    "dataset_id": "$(json_escape "${DATASET_ID:-}")",
    "dataset_name": "$(json_escape "${DATASET_NAME:-}")",
    "item_count": ${ITEM_COUNT:-0},
    "job_exists": $JOB_EXISTS,
    "job_name": "$(json_escape "${JOB_NAME:-}")",
    "job_desc": "$(json_escape "${JOB_DESC:-}")",
    "cron_expr": "$(json_escape "${CRON_EXPR:-}")",
    "audit_log_count": ${AUDIT_LOG_COUNT:-0},
    "audit_baseline_count": ${AUDIT_BASELINE_COUNT:-0},
    "result_nonce": "$(cat /tmp/result_nonce 2>/dev/null || echo "")"
}
EOF

rm -f /tmp/automated_safety_extract_result.json 2>/dev/null || sudo rm -f /tmp/automated_safety_extract_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/automated_safety_extract_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/automated_safety_extract_result.json
chmod 666 /tmp/automated_safety_extract_result.json 2>/dev/null || sudo chmod 666 /tmp/automated_safety_extract_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete."
cat /tmp/automated_safety_extract_result.json