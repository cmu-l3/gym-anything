#!/bin/bash
echo "=== Exporting Record Lab Results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ORDER_ID=50001

# ------------------------------------------------------------------
# 1. DATABASE EXTRACTION
# ------------------------------------------------------------------

# Check if a report exists for this order
REPORT_JSON=$(librehealth_query "SELECT JSON_OBJECT(
    'report_id', procedure_report_id,
    'date_report', date_report,
    'status', report_status,
    'source', source
) FROM procedure_report WHERE procedure_order_id = $ORDER_ID LIMIT 1")

if [ -z "$REPORT_JSON" ]; then
    REPORT_JSON="null"
fi

# Get all results for this order (linked via report)
# We join procedure_result with procedure_type to get the test names
RESULTS_JSON=$(librehealth_query "SELECT JSON_ARRAYAGG(JSON_OBJECT(
    'result_name', pt.name,
    'result_value', pr.result_text,
    'units', pr.units,
    'abnormal', pr.abnormal
)) 
FROM procedure_report rep
JOIN procedure_result pr ON rep.procedure_report_id = pr.procedure_report_id
JOIN procedure_type pt ON pr.procedure_type_id = pt.procedure_type_id
WHERE rep.procedure_order_id = $ORDER_ID")

if [ -z "$RESULTS_JSON" ] || [ "$RESULTS_JSON" == "NULL" ]; then
    RESULTS_JSON="[]"
fi

# ------------------------------------------------------------------
# 2. APP STATE
# ------------------------------------------------------------------
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# ------------------------------------------------------------------
# 3. EXPORT JSON
# ------------------------------------------------------------------
take_screenshot /tmp/task_final.png

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $(date +%s),
    "app_running": $APP_RUNNING,
    "order_id": $ORDER_ID,
    "report": $REPORT_JSON,
    "results": $RESULTS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Exported Data:"
cat /tmp/task_result.json
echo "=== Export Complete ==="