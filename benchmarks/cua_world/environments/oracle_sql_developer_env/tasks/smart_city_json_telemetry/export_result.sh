#!/bin/bash
# Export results for Smart City JSON Telemetry task
echo "=== Exporting JSON Telemetry results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Initialize flags and counts
IS_JSON_CONSTRAINT=false
METER_EVENTS_EXISTS=false
METER_EVENTS_COUNT=0
PAYMENT_VW_EXISTS=false
PAYMENT_VW_COUNT=0
DISPATCH_EXISTS=false
DISPATCH_COUNT=0
CSV_EXISTS=false
CSV_SIZE=0

# --- Check IS JSON constraint ---
# Query the view that handles long text values for check conditions
CONSTRAINT_CHECK=$(oracle_query_raw "
SELECT COUNT(*) 
FROM all_constraints 
WHERE owner = 'CITY_ANALYST' 
  AND table_name = 'METER_TELEMETRY_STG' 
  AND constraint_type = 'C' 
  AND UPPER(search_condition_vc) LIKE '%IS JSON%';
" "system" | tr -d '[:space:]')

if [ "${CONSTRAINT_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    IS_JSON_CONSTRAINT=true
fi

# --- Check METER_EVENTS table ---
ME_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'CITY_ANALYST' AND table_name = 'METER_EVENTS';" "system" | tr -d '[:space:]')
if [ "${ME_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    METER_EVENTS_EXISTS=true
    METER_EVENTS_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM city_analyst.meter_events;" "system" | tr -d '[:space:]')
    if [[ ! "$METER_EVENTS_COUNT" =~ ^[0-9]+$ ]]; then METER_EVENTS_COUNT=0; fi
fi

# --- Check PAYMENT_RECONCILIATION_VW ---
VW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'CITY_ANALYST' AND view_name = 'PAYMENT_RECONCILIATION_VW';" "system" | tr -d '[:space:]')
if [ "${VW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PAYMENT_VW_EXISTS=true
    # The setup data contains exactly 5 records with discrepancies
    PAYMENT_VW_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM city_analyst.payment_reconciliation_vw;" "system" | tr -d '[:space:]')
    if [[ ! "$PAYMENT_VW_COUNT" =~ ^[0-9]+$ ]]; then PAYMENT_VW_COUNT=0; fi
fi

# --- Check MAINTENANCE_DISPATCH table ---
MD_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'CITY_ANALYST' AND table_name = 'MAINTENANCE_DISPATCH';" "system" | tr -d '[:space:]')
if [ "${MD_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    DISPATCH_EXISTS=true
    # The setup data contains 8 total hardware faults when flattened
    DISPATCH_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM city_analyst.maintenance_dispatch;" "system" | tr -d '[:space:]')
    if [[ ! "$DISPATCH_COUNT" =~ ^[0-9]+$ ]]; then DISPATCH_COUNT=0; fi
fi

# --- Check CSV Export ---
CSV_PATH="/home/ga/Documents/exports/maintenance_dispatch.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
fi

# Collect GUI usage evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# Create JSON output
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "is_json_constraint": $IS_JSON_CONSTRAINT,
    "meter_events_exists": $METER_EVENTS_EXISTS,
    "meter_events_count": $METER_EVENTS_COUNT,
    "payment_vw_exists": $PAYMENT_VW_EXISTS,
    "payment_vw_count": $PAYMENT_VW_COUNT,
    "dispatch_exists": $DISPATCH_EXISTS,
    "dispatch_count": $DISPATCH_COUNT,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    $GUI_EVIDENCE
}
EOF

# Move to final location safely
rm -f /tmp/json_telemetry_result.json 2>/dev/null || sudo rm -f /tmp/json_telemetry_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/json_telemetry_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/json_telemetry_result.json
chmod 666 /tmp/json_telemetry_result.json 2>/dev/null || sudo chmod 666 /tmp/json_telemetry_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/json_telemetry_result.json"
cat /tmp/json_telemetry_result.json

echo "=== Export Complete ==="