#!/bin/bash
echo "=== Exporting Clickstream Funnel Analysis results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Helper to execute query as system and trim output
run_query() {
    oracle_query_raw "$1" "system" 2>/dev/null | tr -d '[:space:]'
}

# 1. Check USER_SESSIONS table
USER_SESSIONS_EXISTS="false"
USER_SESSIONS_ROWS=0
if [ "$(run_query "SELECT COUNT(*) FROM all_tables WHERE owner='CLICK_ANALYST' AND table_name='USER_SESSIONS';")" -gt 0 ]; then
    USER_SESSIONS_EXISTS="true"
    USER_SESSIONS_ROWS=$(run_query "SELECT COUNT(*) FROM click_analyst.user_sessions;")
fi

# 2. Check FUNNEL_PATTERNS table
FUNNEL_PATTERNS_EXISTS="false"
FUNNEL_PATTERNS_ROWS=0
PATTERN_TYPES_COUNT=0
if [ "$(run_query "SELECT COUNT(*) FROM all_tables WHERE owner='CLICK_ANALYST' AND table_name='FUNNEL_PATTERNS';")" -gt 0 ]; then
    FUNNEL_PATTERNS_EXISTS="true"
    FUNNEL_PATTERNS_ROWS=$(run_query "SELECT COUNT(*) FROM click_analyst.funnel_patterns;")
    # Attempt to count distinct patterns if column exists
    PATTERN_TYPES_COUNT=$(run_query "SELECT COUNT(DISTINCT pattern_type) FROM click_analyst.funnel_patterns;" 2>/dev/null || echo "0")
fi

# 3. Check USER_SEGMENTS table
USER_SEGMENTS_EXISTS="false"
USER_SEGMENTS_ROWS=0
if [ "$(run_query "SELECT COUNT(*) FROM all_tables WHERE owner='CLICK_ANALYST' AND table_name='USER_SEGMENTS';")" -gt 0 ]; then
    USER_SEGMENTS_EXISTS="true"
    USER_SEGMENTS_ROWS=$(run_query "SELECT COUNT(*) FROM click_analyst.user_segments;")
fi

# 4. Check CONVERSION_FUNNEL_VW
CONVERSION_VW_EXISTS="false"
if [ "$(run_query "SELECT COUNT(*) FROM all_views WHERE owner='CLICK_ANALYST' AND view_name='CONVERSION_FUNNEL_VW';")" -gt 0 ]; then
    CONVERSION_VW_EXISTS="true"
fi

# 5. Check ENGAGEMENT_DASHBOARD_MV and Window Functions
ENGAGEMENT_MV_EXISTS="false"
WINDOW_FUNC_USED="false"
if [ "$(run_query "SELECT COUNT(*) FROM all_mviews WHERE owner='CLICK_ANALYST' AND mview_name='ENGAGEMENT_DASHBOARD_MV';")" -gt 0 ]; then
    ENGAGEMENT_MV_EXISTS="true"
    MV_TEXT=$(oracle_query_raw "SELECT query FROM dba_mviews WHERE owner='CLICK_ANALYST' AND mview_name='ENGAGEMENT_DASHBOARD_MV';" "system" 2>/dev/null)
    if echo "$MV_TEXT" | grep -qiE "OVER\s*\("; then
        WINDOW_FUNC_USED="true"
    fi
fi

# 6. Check for MATCH_RECOGNIZE or LAG/LEAD
PATTERN_MATCH_USED="false"
SRC_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner='CLICK_ANALYST' UNION SELECT text FROM all_source WHERE owner='CLICK_ANALYST';" "system" 2>/dev/null)
if echo "$SRC_TEXT" | grep -qiE "MATCH_RECOGNIZE|LAG\s*\(|LEAD\s*\("; then
    PATTERN_MATCH_USED="true"
fi

# 7. Check CSV Export
CSV_EXISTS="false"
CSV_SIZE=0
CSV_PATH="/home/ga/funnel_report.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_EXISTS="true"
        CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
    fi
fi

# 8. GUI Evidence
GUI_EVIDENCE=$(collect_gui_evidence 2>/dev/null || echo "{}")
if [ -z "$GUI_EVIDENCE" ] || [ "$GUI_EVIDENCE" = "{}" ]; then
    GUI_EVIDENCE='{"mru_connection_count": 0, "sqldev_oracle_sessions": 0, "sql_history_count": 0}'
fi

# Create JSON output
TEMP_JSON=$(mktemp /tmp/clickstream_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "user_sessions_exists": $USER_SESSIONS_EXISTS,
    "user_sessions_rows": ${USER_SESSIONS_ROWS:-0},
    "funnel_patterns_exists": $FUNNEL_PATTERNS_EXISTS,
    "funnel_patterns_rows": ${FUNNEL_PATTERNS_ROWS:-0},
    "pattern_types_count": ${PATTERN_TYPES_COUNT:-0},
    "user_segments_exists": $USER_SEGMENTS_EXISTS,
    "user_segments_rows": ${USER_SEGMENTS_ROWS:-0},
    "conversion_vw_exists": $CONVERSION_VW_EXISTS,
    "engagement_mv_exists": $ENGAGEMENT_MV_EXISTS,
    "window_func_used": $WINDOW_FUNC_USED,
    "pattern_match_used": $PATTERN_MATCH_USED,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "gui_evidence": {$(echo "$GUI_EVIDENCE" | sed -n '/{/,/}/p' | sed '1d;$d')}
}
EOF

# Move JSON and adjust permissions
rm -f /tmp/clickstream_result.json 2>/dev/null || sudo rm -f /tmp/clickstream_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/clickstream_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/clickstream_result.json
chmod 666 /tmp/clickstream_result.json 2>/dev/null || sudo chmod 666 /tmp/clickstream_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results saved to /tmp/clickstream_result.json"
cat /tmp/clickstream_result.json
echo "=== Export complete ==="