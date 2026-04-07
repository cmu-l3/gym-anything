#!/bin/bash
echo "=== Exporting Property Assessment Equalization Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png ga

# Initialize all flags
RATIO_STUDY_VW_EXISTS=false
WINDOW_FUNC_USED=false
EQUALIZATION_FACTORS_EXISTS=false
FACTORS_CORRECT=false
FACTORS_APPLIED_STATUS=false
MERGE_USED=false
ASSESSMENTS_UPDATED=false
UNPIVOT_VW_EXISTS=false
UNPIVOT_USED=false
LISTAGG_VW_EXISTS=false
LISTAGG_USED=false
CSV_EXISTS=false
CSV_SIZE=0

# --- Check RATIO_STUDY_VW ---
RS_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'COUNTY_ASSESSOR' AND view_name = 'RATIO_STUDY_VW';" "system" | tr -d '[:space:]')
if [ "${RS_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    RATIO_STUDY_VW_EXISTS=true
    
    # Check for window functions (PERCENTILE_CONT or OVER)
    RS_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'COUNTY_ASSESSOR' AND view_name = 'RATIO_STUDY_VW';" "system" 2>/dev/null)
    if echo "$RS_TEXT" | grep -qiE "PERCENTILE_CONT|OVER\s*\(|PARTITION\s+BY" 2>/dev/null; then
        WINDOW_FUNC_USED=true
    fi
fi

# --- Check EQUALIZATION_FACTORS ---
EF_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'COUNTY_ASSESSOR' AND table_name = 'EQUALIZATION_FACTORS';" "system" | tr -d '[:space:]')
if [ "${EF_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    EQUALIZATION_FACTORS_EXISTS=true
    
    # Check if the factors are mathematically correct (equalization_factor ≈ target_ratio / current_median_ratio)
    # Target ratio is 0.33
    FACTORS_MATH_ERRORS=$(oracle_query_raw "SELECT COUNT(*) FROM county_assessor.equalization_factors WHERE ABS(equalization_factor - (target_ratio / current_median_ratio)) > 0.05 AND current_median_ratio > 0;" "system" | tr -d '[:space:]')
    FACTORS_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM county_assessor.equalization_factors;" "system" | tr -d '[:space:]')
    
    if [ "${FACTORS_COUNT:-0}" -gt 0 ] 2>/dev/null && [ "${FACTORS_MATH_ERRORS:-99}" = "0" ] 2>/dev/null; then
        FACTORS_CORRECT=true
    fi
    
    # Check status
    STATUS_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM county_assessor.equalization_factors WHERE UPPER(status) = 'APPLIED';" "system" | tr -d '[:space:]')
    if [ "${STATUS_CHECK:-0}" -gt 0 ] 2>/dev/null; then
        FACTORS_APPLIED_STATUS=true
    fi
fi

# --- Check if MERGE was used ---
SQL_HISTORY_DIR="/home/ga/.sqldeveloper/SqlHistory"
if [ -d "$SQL_HISTORY_DIR" ]; then
    if grep -qi "MERGE\s\+INTO" "$SQL_HISTORY_DIR"/*.xml 2>/dev/null; then
        MERGE_USED=true
    fi
fi

# Check ALL_SOURCE as fallback (if they saved it in a procedure, though task just said write a statement)
SRC_TEXT=$(oracle_query_raw "SELECT text FROM all_source WHERE owner = 'COUNTY_ASSESSOR' ORDER BY name, type, line;" "system" 2>/dev/null)
if echo "$SRC_TEXT" | grep -qiE "MERGE\s+INTO" 2>/dev/null; then
    MERGE_USED=true
fi

# Check active session SQL history (if still in memory)
SESSIONS_TEXT=$(oracle_query_raw "SELECT sql_text FROM v\$sql WHERE UPPER(sql_text) LIKE '%MERGE%INTO%ASSESSMENTS%';" "system" 2>/dev/null)
if echo "$SESSIONS_TEXT" | grep -qiE "MERGE\s+INTO" 2>/dev/null; then
    MERGE_USED=true
fi

# --- Check if Assessments were updated ---
CURRENT_ASSESSMENT_SUM=$(oracle_query_raw "SELECT SUM(total_assessed_value) FROM county_assessor.assessments WHERE tax_year = 2024;" "system" | tr -d '[:space:]')
INITIAL_ASSESSMENT_SUM=$(cat /tmp/initial_assessment_sum.txt 2>/dev/null || echo "0")

# If current sum is different from initial sum (by more than a rounding margin), it was updated
if [ "$CURRENT_ASSESSMENT_SUM" != "$INITIAL_ASSESSMENT_SUM" ] && [ -n "$CURRENT_ASSESSMENT_SUM" ] && [ "$CURRENT_ASSESSMENT_SUM" != "ERROR" ]; then
    ASSESSMENTS_UPDATED=true
fi

# --- Check UNPIVOT view ---
UNPIVOT_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'COUNTY_ASSESSOR' AND view_name = 'PROPERTY_CHARS_UNPIVOT_VW';" "system" | tr -d '[:space:]')
if [ "${UNPIVOT_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    UNPIVOT_VW_EXISTS=true
    
    UP_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'COUNTY_ASSESSOR' AND view_name = 'PROPERTY_CHARS_UNPIVOT_VW';" "system" 2>/dev/null)
    if echo "$UP_TEXT" | grep -qiE "UNPIVOT" 2>/dev/null; then
        UNPIVOT_USED=true
    fi
fi

# --- Check LISTAGG view ---
LISTAGG_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'COUNTY_ASSESSOR' AND view_name = 'PARCEL_TAX_SUMMARY_VW';" "system" | tr -d '[:space:]')
if [ "${LISTAGG_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    LISTAGG_VW_EXISTS=true
    
    LA_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'COUNTY_ASSESSOR' AND view_name = 'PARCEL_TAX_SUMMARY_VW';" "system" 2>/dev/null)
    if echo "$LA_TEXT" | grep -qiE "LISTAGG" 2>/dev/null; then
        LISTAGG_USED=true
    fi
fi

# --- Check CSV export ---
CSV_PATH="/home/ga/equalization_report.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS=true
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
fi

# Get GUI evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "ratio_study_vw_exists": $RATIO_STUDY_VW_EXISTS,
    "window_func_used": $WINDOW_FUNC_USED,
    "equalization_factors_exists": $EQUALIZATION_FACTORS_EXISTS,
    "factors_correct": $FACTORS_CORRECT,
    "factors_applied_status": $FACTORS_APPLIED_STATUS,
    "merge_used": $MERGE_USED,
    "assessments_updated": $ASSESSMENTS_UPDATED,
    "unpivot_vw_exists": $UNPIVOT_VW_EXISTS,
    "unpivot_used": $UNPIVOT_USED,
    "listagg_vw_exists": $LISTAGG_VW_EXISTS,
    "listagg_used": $LISTAGG_USED,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "initial_assessment_sum": "$INITIAL_ASSESSMENT_SUM",
    "current_assessment_sum": "$CURRENT_ASSESSMENT_SUM",
    $GUI_EVIDENCE
}
EOF

# Move to final location safely
rm -f /tmp/equalization_result.json 2>/dev/null || sudo rm -f /tmp/equalization_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/equalization_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/equalization_result.json
chmod 666 /tmp/equalization_result.json 2>/dev/null || sudo chmod 666 /tmp/equalization_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/equalization_result.json"
cat /tmp/equalization_result.json