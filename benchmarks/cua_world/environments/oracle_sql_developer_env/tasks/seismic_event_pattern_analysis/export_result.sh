#!/bin/bash
# Export script for Seismic Event Pattern Analysis task
echo "=== Exporting Seismic Analysis results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize flags
FMA_VIEW_EXISTS=false
MATCH_RECOGNIZE_USED=false
FMA_HAS_DATA=false
BVALUE_VIEW_EXISTS=false
REGR_SLOPE_USED=false
BVALUE_REASONABLE=false
SWARM_VIEW_EXISTS=false
WINDOW_FUNC_USED=false
ALERTS_TABLE_EXISTS=false
PROC_EXISTS=false
PROC_VALID=false
JOB_EXISTS=false
CSV_EXISTS=false
CSV_CONTENT_VALID=false

# 1. Check FMA_SEQUENCES view
FMA_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'SEISMO' AND view_name = 'FMA_SEQUENCES';" "system" | tr -d '[:space:]')
if [ "${FMA_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    FMA_VIEW_EXISTS=true
    
    VW_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'SEISMO' AND view_name = 'FMA_SEQUENCES';" "system" 2>/dev/null)
    if echo "$VW_TEXT" | grep -qiE "MATCH_RECOGNIZE" 2>/dev/null; then
        MATCH_RECOGNIZE_USED=true
    fi
    
    FMA_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM seismo.fma_sequences;" "system" | tr -d '[:space:]')
    if [ "${FMA_COUNT:-0}" -gt 0 ] 2>/dev/null; then
        FMA_HAS_DATA=true
    fi
fi

# 2. Check GR_BVALUE_ANALYSIS view
BVAL_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'SEISMO' AND view_name = 'GR_BVALUE_ANALYSIS';" "system" | tr -d '[:space:]')
if [ "${BVAL_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    BVALUE_VIEW_EXISTS=true
    
    VW_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'SEISMO' AND view_name = 'GR_BVALUE_ANALYSIS';" "system" 2>/dev/null)
    if echo "$VW_TEXT" | grep -qiE "REGR_SLOPE|REGR_" 2>/dev/null; then
        REGR_SLOPE_USED=true
    fi
    
    # Check if b-values are between 0.2 and 2.5 (scientifically plausible range)
    BVAL_VALID_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM seismo.gr_bvalue_analysis WHERE b_value BETWEEN 0.2 AND 2.5;" "system" | tr -d '[:space:]')
    if [ "${BVAL_VALID_COUNT:-0}" -gt 0 ] 2>/dev/null; then
        BVALUE_REASONABLE=true
    fi
fi

# 3. Check SWARM_DETECTION view
SWARM_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'SEISMO' AND view_name = 'SWARM_DETECTION';" "system" | tr -d '[:space:]')
if [ "${SWARM_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    SWARM_VIEW_EXISTS=true
    
    VW_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'SEISMO' AND view_name = 'SWARM_DETECTION';" "system" 2>/dev/null)
    if echo "$VW_TEXT" | grep -qiE "OVER\s*\(.*RANGE BETWEEN|OVER\s*\(.*ROWS BETWEEN" 2>/dev/null; then
        WINDOW_FUNC_USED=true
    fi
fi

# 4. Check SEISMICITY_ALERTS table
ALERTS_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'SEISMO' AND table_name = 'SEISMICITY_ALERTS';" "system" | tr -d '[:space:]')
if [ "${ALERTS_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    ALERTS_TABLE_EXISTS=true
fi

# 5. Check PROC_CHECK_SEISMIC_ANOMALIES procedure
PROC_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_procedures WHERE owner = 'SEISMO' AND object_name = 'PROC_CHECK_SEISMIC_ANOMALIES';" "system" | tr -d '[:space:]')
if [ "${PROC_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PROC_EXISTS=true
    
    PROC_VALID_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_objects WHERE owner = 'SEISMO' AND object_name = 'PROC_CHECK_SEISMIC_ANOMALIES' AND status = 'VALID';" "system" | tr -d '[:space:]')
    if [ "${PROC_VALID_CHECK:-0}" -gt 0 ] 2>/dev/null; then
        PROC_VALID=true
    fi
fi

# 6. Check SEISMIC_MONITOR scheduler job
JOB_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_scheduler_jobs WHERE owner = 'SEISMO' AND job_name = 'SEISMIC_MONITOR';" "system" | tr -d '[:space:]')
if [ "${JOB_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    JOB_EXISTS=true
fi

# 7. Check CSV export
CSV_PATH="/home/ga/seismic_report.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS=true
    if grep -qi "region" "$CSV_PATH" && grep -qi "b_value" "$CSV_PATH"; then
        CSV_CONTENT_VALID=true
    fi
fi

# 8. Check GUI Evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# Create JSON output
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "fma_view_exists": $FMA_VIEW_EXISTS,
    "match_recognize_used": $MATCH_RECOGNIZE_USED,
    "fma_has_data": $FMA_HAS_DATA,
    "bvalue_view_exists": $BVALUE_VIEW_EXISTS,
    "regr_slope_used": $REGR_SLOPE_USED,
    "bvalue_reasonable": $BVALUE_REASONABLE,
    "swarm_view_exists": $SWARM_VIEW_EXISTS,
    "window_func_used": $WINDOW_FUNC_USED,
    "alerts_table_exists": $ALERTS_TABLE_EXISTS,
    "proc_exists": $PROC_EXISTS,
    "proc_valid": $PROC_VALID,
    "job_exists": $JOB_EXISTS,
    "csv_exists": $CSV_EXISTS,
    "csv_content_valid": $CSV_CONTENT_VALID,
    $GUI_EVIDENCE
}
EOF

rm -f /tmp/seismic_result.json 2>/dev/null || sudo rm -f /tmp/seismic_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/seismic_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/seismic_result.json
chmod 666 /tmp/seismic_result.json 2>/dev/null || sudo chmod 666 /tmp/seismic_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/seismic_result.json"
cat /tmp/seismic_result.json
echo "=== Export complete ==="