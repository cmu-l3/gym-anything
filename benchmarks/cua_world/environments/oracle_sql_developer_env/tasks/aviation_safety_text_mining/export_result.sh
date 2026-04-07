#!/bin/bash
echo "=== Exporting Aviation Safety Text Mining Results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png ga

# Helper function to query LONG text fields safely
query_long_text() {
    sudo docker exec -i oracle-xe bash -c "sqlplus -s aviation/Aviation2024@localhost:1521/XEPDB1 << 'EOF'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LINESIZE 32767 LONG 2000000
$1
EOF"
}

# 1. Check Stoplist
STOPWORDS=$(query_long_text "SELECT spw_word FROM ctx_user_stopwords WHERE spw_stoplist = 'ASRS_STOPLIST';")

# 2. Check Index
IDX_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM ctx_user_indexes WHERE idx_name = 'IDX_ASRS_NARRATIVE' AND idx_type = 'CONTEXT';" "aviation" "Aviation2024" | tr -d '[:space:]')
IDX_EXISTS="false"
if [ "${IDX_CHECK:-0}" -gt 0 ]; then IDX_EXISTS="true"; fi

# 3. Check Views
THREAT_VW_EXISTS="false"
THREAT_VW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM user_views WHERE view_name = 'DRONE_LASER_THREATS_VW';" "aviation" "Aviation2024" | tr -d '[:space:]')
if [ "${THREAT_VW_CHECK:-0}" -gt 0 ]; then THREAT_VW_EXISTS="true"; fi
THREAT_VW_TEXT=$(query_long_text "SELECT text FROM user_views WHERE view_name = 'DRONE_LASER_THREATS_VW';")

ALT_MV_EXISTS="false"
ALT_MV_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM user_mviews WHERE mview_name = 'EXTRACTED_ALTITUDES_MV';" "aviation" "Aviation2024" | tr -d '[:space:]')
if [ "${ALT_MV_CHECK:-0}" -gt 0 ]; then ALT_MV_EXISTS="true"; fi
ALT_MV_TEXT=$(query_long_text "SELECT query FROM user_mviews WHERE mview_name = 'EXTRACTED_ALTITUDES_MV';")

# Fetch a few extracted altitudes to verify regex success
ALT_MV_ROWS=$(query_long_text "SELECT reported_altitude FROM EXTRACTED_ALTITUDES_MV WHERE ROWNUM <= 5 AND reported_altitude IS NOT NULL;")

# 4. Check Procedure
PROC_EXISTS="false"
PROC_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM user_procedures WHERE object_name = 'PROC_SYNC_TEXT_INDEX';" "aviation" "Aviation2024" | tr -d '[:space:]')
if [ "${PROC_CHECK:-0}" -gt 0 ]; then PROC_EXISTS="true"; fi
PROC_TEXT=$(query_long_text "SELECT text FROM user_source WHERE name = 'PROC_SYNC_TEXT_INDEX' ORDER BY line;")

# 5. Check CSV Export
CSV_PATH="/home/ga/Documents/exports/threat_reports.csv"
CSV_EXISTS="false"
CSV_SIZE=0
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
fi

# 6. Check GUI Usage
GUI_EVIDENCE=$(collect_gui_evidence)

# Create JSON Export File safely using Python
python3 << EOF
import json
import sys

# Format inputs
stopwords = """$STOPWORDS""".strip().split()
threat_vw_text = """$THREAT_VW_TEXT"""
alt_mv_text = """$ALT_MV_TEXT"""
alt_mv_rows = """$ALT_MV_ROWS""".strip().split()
proc_text = """$PROC_TEXT"""

gui_evidence_raw = """$GUI_EVIDENCE"""
try:
    gui_dict = json.loads("{" + gui_evidence_raw + "}")['gui_evidence']
except:
    gui_dict = {}

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "stopwords": stopwords,
    "index_exists": "$IDX_EXISTS" == "true",
    "threat_vw_exists": "$THREAT_VW_EXISTS" == "true",
    "threat_vw_text": threat_vw_text,
    "alt_mv_exists": "$ALT_MV_EXISTS" == "true",
    "alt_mv_text": alt_mv_text,
    "extracted_altitudes": alt_mv_rows,
    "proc_exists": "$PROC_EXISTS" == "true",
    "proc_text": proc_text,
    "csv_exists": "$CSV_EXISTS" == "true",
    "csv_size_bytes": $CSV_SIZE,
    "gui_evidence": gui_dict
}

with open('/tmp/aviation_safety_result.json', 'w') as f:
    json.dump(result, f, indent=2)
EOF

chmod 666 /tmp/aviation_safety_result.json
echo "Results exported to /tmp/aviation_safety_result.json"
echo "=== Export Complete ==="