#!/bin/bash
echo "=== Exporting Airline Crew Fatigue Audit Results ==="

source /workspace/scripts/task_utils.sh

# Record end time and take screenshot
TASK_END=$(date +%s)
take_screenshot /tmp/task_final_state.png

# Initialize tracking variables
REST_VW_EXISTS="false"
LEAD_USED="false"
ROLLING_VW_EXISTS="false"
RANGE_USED="false"
TABLE_EXISTS="false"
PROC_EXISTS="false"
REST_VIOLATION_COUNT=0
LIMIT_VIOLATION_COUNT=0
CSV_EXISTS="false"
CSV_SIZE=0

# -------------------------------------------------------------------
# 1. Check Views and Syntax
# -------------------------------------------------------------------
REST_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'AVIATION_AUDIT' AND view_name = 'CREW_REST_PERIODS_VW';" "system" | tr -d '[:space:]')
if [ "${REST_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    REST_VW_EXISTS="true"
    # Check for LEAD() function
    REST_TEXT=$(oracle_query_raw "SELECT UPPER(text) FROM all_views WHERE owner = 'AVIATION_AUDIT' AND view_name = 'CREW_REST_PERIODS_VW';" "system" 2>/dev/null)
    if echo "$REST_TEXT" | grep -qE "LEAD\s*\("; then
        LEAD_USED="true"
    fi
fi

ROLL_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'AVIATION_AUDIT' AND view_name = 'ROLLING_FLIGHT_HOURS_VW';" "system" | tr -d '[:space:]')
if [ "${ROLL_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    ROLLING_VW_EXISTS="true"
    # Check for RANGE windowing
    ROLL_TEXT=$(oracle_query_raw "SELECT UPPER(text) FROM all_views WHERE owner = 'AVIATION_AUDIT' AND view_name = 'ROLLING_FLIGHT_HOURS_VW';" "system" 2>/dev/null)
    if echo "$ROLL_TEXT" | grep -qE "RANGE\s+BETWEEN\s+[0-9]+\s+PRECEDING"; then
        RANGE_USED="true"
    fi
fi

# -------------------------------------------------------------------
# 2. Check Table and Procedure
# -------------------------------------------------------------------
TBL_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'AVIATION_AUDIT' AND table_name = 'FAA_VIOLATION_REPORT';" "system" | tr -d '[:space:]')
if [ "${TBL_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    TABLE_EXISTS="true"
    
    # Query actual records inserted by the agent
    REST_VIOLATION_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM aviation_audit.faa_violation_report WHERE violation_type = 'INSUFFICIENT_REST';" "system" | tr -d '[:space:]')
    REST_VIOLATION_COUNT=${REST_VIOLATION_COUNT:-0}
    
    LIMIT_VIOLATION_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM aviation_audit.faa_violation_report WHERE violation_type = 'EXCEEDED_28D_LIMIT';" "system" | tr -d '[:space:]')
    LIMIT_VIOLATION_COUNT=${LIMIT_VIOLATION_COUNT:-0}
fi

PROC_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_procedures WHERE owner = 'AVIATION_AUDIT' AND object_name = 'PROC_AUDIT_VIOLATIONS';" "system" | tr -d '[:space:]')
if [ "${PROC_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PROC_EXISTS="true"
fi

# -------------------------------------------------------------------
# 3. Check CSV Export
# -------------------------------------------------------------------
CSV_PATH="/home/ga/Documents/faa_audit_report.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c%s "$CSV_PATH" 2>/dev/null || echo "0")
fi

# -------------------------------------------------------------------
# 4. Check GUI Usage
# -------------------------------------------------------------------
GUI_EVIDENCE=$(collect_gui_evidence)

# -------------------------------------------------------------------
# 5. Build Result JSON
# -------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "rest_vw_exists": $REST_VW_EXISTS,
    "lead_used": $LEAD_USED,
    "rolling_vw_exists": $ROLLING_VW_EXISTS,
    "range_used": $RANGE_USED,
    "table_exists": $TABLE_EXISTS,
    "proc_exists": $PROC_EXISTS,
    "rest_violation_count": $REST_VIOLATION_COUNT,
    "limit_violation_count": $LIMIT_VIOLATION_COUNT,
    "csv_exists": $CSV_EXISTS,
    "csv_size_bytes": $CSV_SIZE,
    $GUI_EVIDENCE
}
EOF

# Move securely to prevent permissions issues
rm -f /tmp/aviation_audit_result.json 2>/dev/null || sudo rm -f /tmp/aviation_audit_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/aviation_audit_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/aviation_audit_result.json
chmod 666 /tmp/aviation_audit_result.json 2>/dev/null || sudo chmod 666 /tmp/aviation_audit_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved."
cat /tmp/aviation_audit_result.json
echo "=== Export Complete ==="