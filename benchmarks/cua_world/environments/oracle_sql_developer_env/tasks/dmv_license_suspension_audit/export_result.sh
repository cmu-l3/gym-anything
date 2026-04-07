#!/bin/bash
# Export results for DMV License Suspension Audit task
echo "=== Exporting DMV Audit results ==="

source /workspace/scripts/task_utils.sh

# Record task end timestamp
date +%s > /tmp/task_end_time
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

take_screenshot /tmp/task_final_screenshot.png ga

# Helper to execute safely and return -1 if error
safe_query() {
    local q="$1"
    local res
    res=$(oracle_query_raw "$q" "system" 2>/dev/null | tr -d '[:space:]')
    if [[ ! "$res" =~ ^-?[0-9]+$ ]]; then
        echo "-1"
    else
        echo "$res"
    fi
}

# --- Check CITATION_ROLLING_POINTS_VW ---
VW_ROLLING_EXISTS="false"
VW_ROLLING_TEXT=""
HAS_RANGE_INTERVAL="false"
HAS_PRECEDING="false"

vw1_chk=$(safe_query "SELECT COUNT(*) FROM all_views WHERE owner = 'DMV_ADMIN' AND view_name = 'CITATION_ROLLING_POINTS_VW';")
if [ "$vw1_chk" -gt 0 ]; then
    VW_ROLLING_EXISTS="true"
    VW_ROLLING_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'DMV_ADMIN' AND view_name = 'CITATION_ROLLING_POINTS_VW';" "system" 2>/dev/null)
    
    # Check for window function keywords
    if echo "$VW_ROLLING_TEXT" | grep -qiE "RANGE\s+BETWEEN\s+INTERVAL"; then
        HAS_RANGE_INTERVAL="true"
    fi
    if echo "$VW_ROLLING_TEXT" | grep -qiE "PRECEDING"; then
        HAS_PRECEDING="true"
    fi
fi

# --- Check LICENSE_AUDIT_VW ---
VW_AUDIT_EXISTS="false"
MISSING_COUNT=-1
INVALID_COUNT=-1
OK_COUNT=-1

vw2_chk=$(safe_query "SELECT COUNT(*) FROM all_views WHERE owner = 'DMV_ADMIN' AND view_name = 'LICENSE_AUDIT_VW';")
if [ "$vw2_chk" -gt 0 ]; then
    VW_AUDIT_EXISTS="true"
    MISSING_COUNT=$(safe_query "SELECT COUNT(*) FROM dmv_admin.license_audit_vw WHERE audit_flag = 'MISSING_SUSPENSION';")
    INVALID_COUNT=$(safe_query "SELECT COUNT(*) FROM dmv_admin.license_audit_vw WHERE audit_flag = 'INVALID_SUSPENSION';")
    OK_COUNT=$(safe_query "SELECT COUNT(*) FROM dmv_admin.license_audit_vw WHERE audit_flag = 'OK';")
fi

# --- Check AUDIT_SUMMARY_MV ---
MV_SUMMARY_EXISTS="false"
MV_MISSING_COUNT=-1
MV_INVALID_COUNT=-1

mv_chk=$(safe_query "SELECT COUNT(*) FROM all_mviews WHERE owner = 'DMV_ADMIN' AND mview_name = 'AUDIT_SUMMARY_MV';")
if [ "$mv_chk" -gt 0 ]; then
    MV_SUMMARY_EXISTS="true"
    # Read the pre-computed summary counts from the MV
    MV_MISSING_COUNT=$(safe_query "SELECT SUM(cnt) FROM (SELECT COUNT(*) as cnt FROM dmv_admin.audit_summary_mv WHERE audit_flag = 'MISSING_SUSPENSION' UNION ALL SELECT 0 FROM dual);")
    MV_INVALID_COUNT=$(safe_query "SELECT SUM(cnt) FROM (SELECT COUNT(*) as cnt FROM dmv_admin.audit_summary_mv WHERE audit_flag = 'INVALID_SUSPENSION' UNION ALL SELECT 0 FROM dual);")
    
    # Handle the case where the group-by didn't return a row (it will be 0 from the union fallback)
fi

# --- Check CSV Export ---
CSV_PATH="/home/ga/Documents/exports/dmv_discrepancies.csv"
CSV_EXISTS="false"
CSV_MODIFIED_DURING_TASK="false"
CSV_SIZE=0
CSV_HAS_MISSING="false"
CSV_HAS_OK="false"

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_MODIFIED_DURING_TASK="true"
    fi
    
    if grep -qi "MISSING_SUSPENSION" "$CSV_PATH"; then
        CSV_HAS_MISSING="true"
    fi
    if grep -qi -E ",OK|OK," "$CSV_PATH"; then
        CSV_HAS_OK="true"
    fi
fi

# Collect GUI evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# Construct JSON output safely
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "vw_rolling_exists": $VW_ROLLING_EXISTS,
    "has_range_interval": $HAS_RANGE_INTERVAL,
    "has_preceding": $HAS_PRECEDING,
    "vw_audit_exists": $VW_AUDIT_EXISTS,
    "audit_counts": {
        "missing": $MISSING_COUNT,
        "invalid": $INVALID_COUNT,
        "ok": $OK_COUNT
    },
    "mv_summary_exists": $MV_SUMMARY_EXISTS,
    "mv_counts": {
        "missing": $MV_MISSING_COUNT,
        "invalid": $MV_INVALID_COUNT
    },
    "csv_export": {
        "exists": $CSV_EXISTS,
        "modified_during_task": $CSV_MODIFIED_DURING_TASK,
        "size_bytes": $CSV_SIZE,
        "has_missing_records": $CSV_HAS_MISSING,
        "has_ok_records": $CSV_HAS_OK
    },
    $GUI_EVIDENCE
}
EOF

# Copy and grant permissions
sudo cp "$TEMP_JSON" /tmp/dmv_audit_result.json
sudo chmod 666 /tmp/dmv_audit_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/dmv_audit_result.json"
cat /tmp/dmv_audit_result.json
echo "=== Export Complete ==="