#!/bin/bash
echo "=== Exporting htt_tandem_repeat_analysis results ==="

TASK_START=$(cat /tmp/htt_task_start_ts 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/UGENE_Data/huntington/results"

DISPLAY=:1 scrot /tmp/htt_end_screenshot.png 2>/dev/null || true

# --- Check Annotated GenBank File ---
GB_FILE="${RESULTS_DIR}/HTT_annotated.gb"
GB_EXISTS=false
GB_VALID=false
TR_ANNOTATION_COUNT=0
CAG_TR_FOUND=false
CAG_REGION_VALID=false

if [ -f "$GB_FILE" ] && [ -s "$GB_FILE" ]; then
    GB_EXISTS=true
    CONTENT=$(cat "$GB_FILE")
    
    if echo "$CONTENT" | grep -q "^LOCUS" && echo "$CONTENT" | grep -q "^FEATURES" && echo "$CONTENT" | grep -q "^ORIGIN"; then
        GB_VALID=true
    fi
    
    TR_ANNOTATION_COUNT=$(echo "$CONTENT" | grep -ciE "repeat_region|tandem_repeat|misc_feature.*repeat" || echo "0")
    
    # Check for CAG motif identification
    if echo "$CONTENT" | grep -i "CAG" | grep -qiE "period=\"3\"|period=3|period.*3"; then
        CAG_TR_FOUND=true
    elif echo "$CONTENT" | grep -qi "CAGCAGCAG"; then
        CAG_TR_FOUND=true
    elif echo "$CONTENT" | grep -qi "CAG" && [ "$TR_ANNOTATION_COUNT" -gt 0 ]; then
        CAG_TR_FOUND=true
    fi
    
    # Verify coordinate location (typically in the 300-800bp range near the start of the CDS)
    if echo "$CONTENT" | grep -iB2 "CAG" | grep -oE '[0-9]+\.\.[0-9]+' | grep -qE '^[1-9][0-9]{2}\.\.[0-9]+'; then
        CAG_REGION_VALID=true
    fi
fi

# --- Check Repeat Table ---
TABLE_FILE_TXT="${RESULTS_DIR}/repeat_table.txt"
TABLE_FILE_CSV="${RESULTS_DIR}/repeat_table.csv"
TABLE_EXISTS=false
TABLE_HAS_DATA=false
TABLE_HAS_PERIOD_3=false

if [ -f "$TABLE_FILE_TXT" ]; then
    TABLE_FILE="$TABLE_FILE_TXT"
elif [ -f "$TABLE_FILE_CSV" ]; then
    TABLE_FILE="$TABLE_FILE_CSV"
else
    TABLE_FILE=""
fi

if [ -n "$TABLE_FILE" ] && [ -s "$TABLE_FILE" ]; then
    TABLE_EXISTS=true
    LINE_COUNT=$(wc -l < "$TABLE_FILE")
    if [ "$LINE_COUNT" -ge 3 ]; then
        TABLE_HAS_DATA=true
    fi
    if grep -w "3" "$TABLE_FILE" >/dev/null || grep -iq "CAG" "$TABLE_FILE"; then
        TABLE_HAS_PERIOD_3=true
    fi
fi

# --- Check Clinical Report ---
REPORT_FILE="${RESULTS_DIR}/clinical_report.txt"
REPORT_EXISTS=false
REPORT_LENGTH=0
REPORT_HAS_CAG_HTT=false
REPORT_HAS_COORDS=false
REPORT_HAS_RANGES=false

if [ -f "$REPORT_FILE" ] && [ -s "$REPORT_FILE" ]; then
    REPORT_EXISTS=true
    REPORT_LENGTH=$(wc -c < "$REPORT_FILE")
    
    CONTENT=$(cat "$REPORT_FILE")
    if echo "$CONTENT" | grep -qi "CAG" && echo "$CONTENT" | grep -qiE "Huntington|HTT|huntingtin"; then
        REPORT_HAS_CAG_HTT=true
    fi
    if echo "$CONTENT" | grep -qE '[0-9]{3}'; then
        REPORT_HAS_COORDS=true
    fi
    if echo "$CONTENT" | grep -qiE '3[5-9]|4[0-9]|range|threshold|pathogenic|normal'; then
        REPORT_HAS_RANGES=true
    fi
fi

# --- Write Results JSON ---
python3 << PYEOF
import json
result = {
    "gb_exists": "${GB_EXISTS}" == "true",
    "gb_valid": "${GB_VALID}" == "true",
    "tr_annotation_count": int("${TR_ANNOTATION_COUNT}"),
    "cag_tr_found": "${CAG_TR_FOUND}" == "true",
    "cag_region_valid": "${CAG_REGION_VALID}" == "true",
    "table_exists": "${TABLE_EXISTS}" == "true",
    "table_has_data": "${TABLE_HAS_DATA}" == "true",
    "table_has_period_3": "${TABLE_HAS_PERIOD_3}" == "true",
    "report_exists": "${REPORT_EXISTS}" == "true",
    "report_length": int("${REPORT_LENGTH}"),
    "report_has_cag_htt": "${REPORT_HAS_CAG_HTT}" == "true",
    "report_has_coords": "${REPORT_HAS_COORDS}" == "true",
    "report_has_ranges": "${REPORT_HAS_RANGES}" == "true"
}
with open("/tmp/htt_task_result.json", "w") as f:
    json.dump(result, f)
PYEOF

echo "=== Export complete ==="