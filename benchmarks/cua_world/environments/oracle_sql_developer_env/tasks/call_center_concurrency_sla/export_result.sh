#!/bin/bash
# Export results for Call Center Concurrency task
echo "=== Exporting Call Center Results ==="

source /workspace/scripts/task_utils.sh

# Record end time & take screenshot
TASK_END=$(date +%s)
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
take_screenshot /tmp/task_end_screenshot.png

# Initialize output JSON variables
INTERVAL_VW_EXISTS="false"
INTERVAL_ROWS="0"
INTERVAL_TEXT=""
PEAK_VW_EXISTS="false"
PEAK_ROWS="0"
PEAK_TEXT=""
REPEAT_VW_EXISTS="false"
REPEAT_ROWS="0"
REPEAT_TEXT=""

# --- 1. Check INTERVAL_SUMMARY_VW ---
if [ "$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='WFM_ANALYST' AND view_name='INTERVAL_SUMMARY_VW';" "system" | tr -d '[:space:]')" -gt 0 ] 2>/dev/null; then
    INTERVAL_VW_EXISTS="true"
    INTERVAL_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM wfm_analyst.interval_summary_vw;" "system" | tr -d '[:space:]' || echo "0")
    INTERVAL_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner='WFM_ANALYST' AND view_name='INTERVAL_SUMMARY_VW';" "system" 2>/dev/null | tr '\n' ' ' | sed 's/"/\\"/g' | sed 's/\s\+/ /g')
fi

# --- 2. Check PEAK_CONCURRENCY_VW ---
if [ "$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='WFM_ANALYST' AND view_name='PEAK_CONCURRENCY_VW';" "system" | tr -d '[:space:]')" -gt 0 ] 2>/dev/null; then
    PEAK_VW_EXISTS="true"
    PEAK_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM wfm_analyst.peak_concurrency_vw;" "system" | tr -d '[:space:]' || echo "0")
    PEAK_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner='WFM_ANALYST' AND view_name='PEAK_CONCURRENCY_VW';" "system" 2>/dev/null | tr '\n' ' ' | sed 's/"/\\"/g' | sed 's/\s\+/ /g')
fi

# --- 3. Check REPEAT_ABANDON_CALLERS_VW ---
if [ "$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='WFM_ANALYST' AND view_name='REPEAT_ABANDON_CALLERS_VW';" "system" | tr -d '[:space:]')" -gt 0 ] 2>/dev/null; then
    REPEAT_VW_EXISTS="true"
    REPEAT_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM wfm_analyst.repeat_abandon_callers_vw;" "system" | tr -d '[:space:]' || echo "0")
    REPEAT_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner='WFM_ANALYST' AND view_name='REPEAT_ABANDON_CALLERS_VW';" "system" 2>/dev/null | tr '\n' ' ' | sed 's/"/\\"/g' | sed 's/\s\+/ /g')
fi

# --- 4. Check CSV Export ---
CSV_PATH="/home/ga/Documents/exports/wfm_interval_summary.csv"
CSV_EXISTS="false"
CSV_CREATED_DURING="false"
CSV_SIZE="0"

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c%s "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -ge "$TASK_START" ]; then
        CSV_CREATED_DURING="true"
    fi
fi

# --- 5. GUI Evidence ---
GUI_EVIDENCE=$(collect_gui_evidence)

# --- 6. Compile JSON Result ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "interval_vw_exists": $INTERVAL_VW_EXISTS,
    "interval_rows": $INTERVAL_ROWS,
    "interval_text": "$INTERVAL_TEXT",
    "peak_vw_exists": $PEAK_VW_EXISTS,
    "peak_rows": $PEAK_ROWS,
    "peak_text": "$PEAK_TEXT",
    "repeat_vw_exists": $REPEAT_VW_EXISTS,
    "repeat_rows": $REPEAT_ROWS,
    "repeat_text": "$REPEAT_TEXT",
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "csv_created_during_task": $CSV_CREATED_DURING,
    $GUI_EVIDENCE
}
EOF

# Handle permissions safely
rm -f /tmp/wfm_result.json 2>/dev/null || sudo rm -f /tmp/wfm_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/wfm_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/wfm_result.json
chmod 666 /tmp/wfm_result.json 2>/dev/null || sudo chmod 666 /tmp/wfm_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/wfm_result.json"
cat /tmp/wfm_result.json
echo "=== Export complete ==="