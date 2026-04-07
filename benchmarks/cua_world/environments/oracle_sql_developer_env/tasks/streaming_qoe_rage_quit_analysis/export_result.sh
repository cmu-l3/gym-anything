#!/bin/bash
# Export results for Streaming QoE & Rage Quit Analysis task
echo "=== Exporting Streaming QoE results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Initialize evaluation flags
PARSED_VW_EXISTS=false
JSON_FUNCS_USED=false
QOE_TABLE_EXISTS=false
QOE_COLS=0
S1_PLAY_SEC=0
RAGE_QUIT_VW_EXISTS=false
MATCH_RECOGNIZE_USED=false
RAGE_QUIT_COUNT=0
RAGE_QUIT_S2=0
RAGE_QUIT_S4=0
ISP_MV_EXISTS=false

# 1. Check PARSED_TELEMETRY_VW
PVW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'STREAM_SRE' AND view_name = 'PARSED_TELEMETRY_VW';" "system" | tr -d '[:space:]')
if [ "${PVW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PARSED_VW_EXISTS=true
    
    # Check for JSON_VALUE or JSON_TABLE
    PVW_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'STREAM_SRE' AND view_name = 'PARSED_TELEMETRY_VW';" "system" 2>/dev/null)
    if echo "$PVW_TEXT" | grep -qiE "JSON_VALUE|JSON_TABLE|\.player_state" 2>/dev/null; then
        JSON_FUNCS_USED=true
    fi
fi

# 2. Check SESSION_QOE_METRICS Table
QOE_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_tables WHERE owner = 'STREAM_SRE' AND table_name = 'SESSION_QOE_METRICS';" "system" | tr -d '[:space:]')
if [ "${QOE_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    QOE_TABLE_EXISTS=true
    
    # Check if correct columns exist
    QOE_COLS=$(oracle_query_raw "SELECT COUNT(*) FROM all_tab_columns WHERE owner='STREAM_SRE' AND table_name='SESSION_QOE_METRICS' AND column_name IN ('TOTAL_PLAYING_SECONDS', 'TOTAL_BUFFERING_SECONDS', 'REBUFFER_RATIO');" "system" | tr -d '[:space:]')
    QOE_COLS=${QOE_COLS:-0}
    
    # Check LEAD logic by looking at known session S1
    S1_PLAY_SEC=$(oracle_query_raw "SELECT total_playing_seconds FROM stream_sre.session_qoe_metrics WHERE session_id = 'S1';" "system" | tr -d '[:space:]')
    S1_PLAY_SEC=${S1_PLAY_SEC:-0}
fi

# 3. Check RAGE_QUIT_ANALYSIS_VW
RQ_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'STREAM_SRE' AND view_name = 'RAGE_QUIT_ANALYSIS_VW';" "system" | tr -d '[:space:]')
if [ "${RQ_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    RAGE_QUIT_VW_EXISTS=true
    
    # Check for MATCH_RECOGNIZE
    RQ_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'STREAM_SRE' AND view_name = 'RAGE_QUIT_ANALYSIS_VW';" "system" 2>/dev/null)
    if echo "$RQ_TEXT" | grep -qiE "MATCH_RECOGNIZE" 2>/dev/null; then
        MATCH_RECOGNIZE_USED=true
    fi
    
    # Evaluate Logic Accuracy (S2 is true positive, S4 is false positive > 120s)
    RAGE_QUIT_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM stream_sre.rage_quit_analysis_vw;" "system" | tr -d '[:space:]')
    RAGE_QUIT_S2=$(oracle_query_raw "SELECT COUNT(*) FROM stream_sre.rage_quit_analysis_vw WHERE session_id = 'S2';" "system" | tr -d '[:space:]')
    RAGE_QUIT_S4=$(oracle_query_raw "SELECT COUNT(*) FROM stream_sre.rage_quit_analysis_vw WHERE session_id = 'S4';" "system" | tr -d '[:space:]')
    
    RAGE_QUIT_COUNT=${RAGE_QUIT_COUNT:-0}
    RAGE_QUIT_S2=${RAGE_QUIT_S2:-0}
    RAGE_QUIT_S4=${RAGE_QUIT_S4:-0}
fi

# 4. Check ISP_DEGRADATION_MV
MV_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_mviews WHERE owner = 'STREAM_SRE' AND mview_name = 'ISP_DEGRADATION_MV';" "system" | tr -d '[:space:]')
if [ "${MV_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    ISP_MV_EXISTS=true
fi

# Collect GUI Evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "parsed_vw_exists": $PARSED_VW_EXISTS,
  "json_funcs_used": $JSON_FUNCS_USED,
  "qoe_table_exists": $QOE_TABLE_EXISTS,
  "qoe_cols_found": $QOE_COLS,
  "s1_play_sec": "$S1_PLAY_SEC",
  "rage_quit_vw_exists": $RAGE_QUIT_VW_EXISTS,
  "match_recognize_used": $MATCH_RECOGNIZE_USED,
  "rage_quit_total": $RAGE_QUIT_COUNT,
  "rage_quit_s2_found": $RAGE_QUIT_S2,
  "rage_quit_s4_found": $RAGE_QUIT_S4,
  "isp_mv_exists": $ISP_MV_EXISTS,
  $GUI_EVIDENCE
}
EOF

# Move to final location safely
rm -f /tmp/streaming_qoe_result.json 2>/dev/null || sudo rm -f /tmp/streaming_qoe_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/streaming_qoe_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/streaming_qoe_result.json
chmod 666 /tmp/streaming_qoe_result.json 2>/dev/null || sudo chmod 666 /tmp/streaming_qoe_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/streaming_qoe_result.json"
cat /tmp/streaming_qoe_result.json
echo "=== Export complete ==="