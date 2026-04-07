#!/bin/bash
echo "=== Exporting Baseball Statcast Pattern Recognition results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Initialize flags
PIVOT_VW_EXISTS=false
PIVOT_USED=false
PIVOT_ROW_COUNT=0

THREE_PITCH_K_VW_EXISTS=false
MATCH_RECOGNIZE_USED=false
THREE_PITCH_K_COUNT=0

FATIGUE_VW_EXISTS=false
PRECEDING_USED=false
FATIGUE_COUNT=0

CSV_EXISTS=false
CSV_SIZE=0

# Check PITCH_ARSENAL_PIVOT_VW
PIVOT_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'BASEBALL_OPS' AND view_name = 'PITCH_ARSENAL_PIVOT_VW';" "system" | tr -d '[:space:]')
if [ "${PIVOT_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PIVOT_VW_EXISTS=true
    PIVOT_ROW_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM baseball_ops.pitch_arsenal_pivot_vw;" "system" | tr -d '[:space:]')
    PIVOT_ROW_COUNT=${PIVOT_ROW_COUNT:-0}
    
    VW_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'BASEBALL_OPS' AND view_name = 'PITCH_ARSENAL_PIVOT_VW';" "system" 2>/dev/null)
    if echo "$VW_TEXT" | grep -qiE "\bPIVOT\b"; then
        PIVOT_USED=true
    fi
fi

# Check THREE_PITCH_K_VW
TP_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'BASEBALL_OPS' AND view_name = 'THREE_PITCH_K_VW';" "system" | tr -d '[:space:]')
if [ "${TP_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    THREE_PITCH_K_VW_EXISTS=true
    THREE_PITCH_K_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM baseball_ops.three_pitch_k_vw;" "system" | tr -d '[:space:]')
    THREE_PITCH_K_COUNT=${THREE_PITCH_K_COUNT:-0}
    
    VW_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'BASEBALL_OPS' AND view_name = 'THREE_PITCH_K_VW';" "system" 2>/dev/null)
    if echo "$VW_TEXT" | grep -qiE "\bMATCH_RECOGNIZE\b"; then
        MATCH_RECOGNIZE_USED=true
    fi
fi

# Check FATIGUE_WARNING_VW
FW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'BASEBALL_OPS' AND view_name = 'FATIGUE_WARNING_VW';" "system" | tr -d '[:space:]')
if [ "${FW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    FATIGUE_VW_EXISTS=true
    FATIGUE_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM baseball_ops.fatigue_warning_vw;" "system" | tr -d '[:space:]')
    FATIGUE_COUNT=${FATIGUE_COUNT:-0}
    
    VW_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'BASEBALL_OPS' AND view_name = 'FATIGUE_WARNING_VW';" "system" 2>/dev/null)
    if echo "$VW_TEXT" | grep -qiE "\bPRECEDING\b"; then
        PRECEDING_USED=true
    fi
fi

# Check CSV export
CSV_PATH="/home/ga/Documents/three_pitch_strikeouts.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS=true
    CSV_SIZE=$(wc -c < "$CSV_PATH" 2>/dev/null || echo 0)
fi

# Collect GUI evidence
GUI_EVIDENCE=$(collect_gui_evidence 2>/dev/null || echo '{"sql_history_count":0,"mru_connection_count":0,"sqldev_oracle_sessions":0}')

# Create JSON output
TEMP_JSON=$(mktemp /tmp/baseball_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "pivot_vw_exists": $PIVOT_VW_EXISTS,
    "pivot_used": $PIVOT_USED,
    "pivot_row_count": $PIVOT_ROW_COUNT,
    "three_pitch_k_vw_exists": $THREE_PITCH_K_VW_EXISTS,
    "match_recognize_used": $MATCH_RECOGNIZE_USED,
    "three_pitch_k_count": $THREE_PITCH_K_COUNT,
    "fatigue_vw_exists": $FATIGUE_VW_EXISTS,
    "preceding_used": $PRECEDING_USED,
    "fatigue_count": $FATIGUE_COUNT,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "gui_evidence": $GUI_EVIDENCE
}
EOF

# Move to final location safely
rm -f /tmp/baseball_result.json 2>/dev/null || sudo rm -f /tmp/baseball_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/baseball_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/baseball_result.json
chmod 666 /tmp/baseball_result.json 2>/dev/null || sudo chmod 666 /tmp/baseball_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results saved to /tmp/baseball_result.json"
cat /tmp/baseball_result.json
echo "=== Export complete ==="