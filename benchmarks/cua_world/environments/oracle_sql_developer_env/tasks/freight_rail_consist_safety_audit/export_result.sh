#!/bin/bash
echo "=== Exporting Freight Rail Consist Safety Audit Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png ga

# Initialize variables
OVERLOADED_CARS_VW_EXISTS=false
OVERLOADED_COUNT=0
TRAIN_POWER_AUDIT_VW_EXISTS=false
UNDERPOWERED_COUNT=0
HAZMAT_VW_EXISTS=false
HAZMAT_COUNT=0
HAZMAT_WINDOW_USED=false
MANIFEST_MV_EXISTS=false
MANIFEST_ROLLUP_USED=false
CSV_EXISTS=false
CSV_SIZE=0

# --- Check OVERLOADED_CARS_VW ---
CHK_OVER=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'RAIL_ADMIN' AND view_name = 'OVERLOADED_CARS_VW';" "system" | tr -d '[:space:]')
if [ "${CHK_OVER:-0}" -gt 0 ] 2>/dev/null; then
    OVERLOADED_CARS_VW_EXISTS=true
    OVERLOADED_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM rail_admin.overloaded_cars_vw;" "system" | tr -d '[:space:]')
    OVERLOADED_COUNT=${OVERLOADED_COUNT:-0}
    if [ "$OVERLOADED_COUNT" = "ERROR" ]; then OVERLOADED_COUNT=0; fi
fi

# --- Check TRAIN_POWER_AUDIT_VW ---
CHK_PWR=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'RAIL_ADMIN' AND view_name = 'TRAIN_POWER_AUDIT_VW';" "system" | tr -d '[:space:]')
if [ "${CHK_PWR:-0}" -gt 0 ] 2>/dev/null; then
    TRAIN_POWER_AUDIT_VW_EXISTS=true
    UNDERPOWERED_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM rail_admin.train_power_audit_vw;" "system" | tr -d '[:space:]')
    UNDERPOWERED_COUNT=${UNDERPOWERED_COUNT:-0}
    if [ "$UNDERPOWERED_COUNT" = "ERROR" ]; then UNDERPOWERED_COUNT=0; fi
fi

# --- Check HAZMAT_VIOLATIONS_VW ---
CHK_HAZ=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'RAIL_ADMIN' AND view_name = 'HAZMAT_VIOLATIONS_VW';" "system" | tr -d '[:space:]')
if [ "${CHK_HAZ:-0}" -gt 0 ] 2>/dev/null; then
    HAZMAT_VW_EXISTS=true
    HAZMAT_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM rail_admin.hazmat_violations_vw;" "system" | tr -d '[:space:]')
    HAZMAT_COUNT=${HAZMAT_COUNT:-0}
    if [ "$HAZMAT_COUNT" = "ERROR" ]; then HAZMAT_COUNT=0; fi
    
    # Check for window function usage (LAG/LEAD)
    VW_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'RAIL_ADMIN' AND view_name = 'HAZMAT_VIOLATIONS_VW';" "system" 2>/dev/null)
    if echo "$VW_TEXT" | grep -qiE "LAG\s*\(|LEAD\s*\("; then
        HAZMAT_WINDOW_USED=true
    fi
fi

# --- Check TRAIN_MANIFEST_SUMMARY_MV ---
CHK_MV=$(oracle_query_raw "SELECT COUNT(*) FROM all_mviews WHERE owner = 'RAIL_ADMIN' AND mview_name = 'TRAIN_MANIFEST_SUMMARY_MV';" "system" | tr -d '[:space:]')
if [ "${CHK_MV:-0}" -gt 0 ] 2>/dev/null; then
    MANIFEST_MV_EXISTS=true
    
    # Check for ROLLUP/CUBE
    MV_TEXT=$(oracle_query_raw "SELECT query FROM all_mviews WHERE owner = 'RAIL_ADMIN' AND mview_name = 'TRAIN_MANIFEST_SUMMARY_MV';" "system" 2>/dev/null)
    if echo "$MV_TEXT" | grep -qiE "ROLLUP|CUBE"; then
        MANIFEST_ROLLUP_USED=true
    fi
fi

# --- Check CSV Export ---
CSV_PATH="/home/ga/Documents/exports/hazmat_audit.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS=true
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
else
    # Fallback search if saved slightly wrong
    FALLBACK=$(find /home/ga/Documents -iname "hazmat_audit.csv" | head -n 1)
    if [ -n "$FALLBACK" ]; then
        CSV_EXISTS=true
        CSV_SIZE=$(stat -c %s "$FALLBACK" 2>/dev/null || echo "0")
    fi
fi

# Collect GUI Evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# --- Build JSON result ---
TEMP_JSON=$(mktemp /tmp/rail_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "overloaded_cars_vw_exists": $OVERLOADED_CARS_VW_EXISTS,
    "overloaded_count": $OVERLOADED_COUNT,
    "train_power_audit_vw_exists": $TRAIN_POWER_AUDIT_VW_EXISTS,
    "underpowered_count": $UNDERPOWERED_COUNT,
    "hazmat_vw_exists": $HAZMAT_VW_EXISTS,
    "hazmat_count": $HAZMAT_COUNT,
    "hazmat_window_used": $HAZMAT_WINDOW_USED,
    "manifest_mv_exists": $MANIFEST_MV_EXISTS,
    "manifest_rollup_used": $MANIFEST_ROLLUP_USED,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    $GUI_EVIDENCE
}
EOF

# Safely copy to /tmp for verifier
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json