#!/bin/bash
echo "=== Exporting ICU Telemetry Pattern Detection Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Initialize flags
PARSED_VITALS_EXISTS=false
CLEAN_VITALS_EXISTS=false
HYPOGLYCEMIA_EXISTS=false
TACHYCARDIA_EXISTS=false
JSON_TABLE_USED=false
IGNORE_NULLS_USED=false
MATCH_RECOGNIZE_USED=false
HYPO_MATCH_COUNT=0
TACHY_MATCH_COUNT=0
CSV_EXISTS=false
CSV_SIZE=0

# Check Views/MViews existence
PARSED_CHK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='CLINICAL_ADMIN' AND view_name='PARSED_VITALS_VW';" "system" | tr -d '[:space:]')
if [ "${PARSED_CHK:-0}" -gt 0 ]; then PARSED_VITALS_EXISTS=true; fi

CLEAN_CHK=$(oracle_query_raw "SELECT COUNT(*) FROM all_mviews WHERE owner='CLINICAL_ADMIN' AND mview_name='CLEAN_VITALS_MV';" "system" | tr -d '[:space:]')
if [ "${CLEAN_CHK:-0}" -gt 0 ]; then CLEAN_VITALS_EXISTS=true; fi

HYPO_CHK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='CLINICAL_ADMIN' AND view_name='HYPOGLYCEMIA_EVENTS_VW';" "system" | tr -d '[:space:]')
if [ "${HYPO_CHK:-0}" -gt 0 ]; then 
    HYPOGLYCEMIA_EXISTS=true
    HYPO_MATCH_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM clinical_admin.hypoglycemia_events_vw;" "system" | tr -d '[:space:]')
    HYPO_MATCH_COUNT=${HYPO_MATCH_COUNT:-0}
fi

TACHY_CHK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='CLINICAL_ADMIN' AND view_name='TACHYCARDIA_TRENDS_VW';" "system" | tr -d '[:space:]')
if [ "${TACHY_CHK:-0}" -gt 0 ]; then 
    TACHYCARDIA_EXISTS=true
    TACHY_MATCH_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM clinical_admin.tachycardia_trends_vw;" "system" | tr -d '[:space:]')
    TACHY_MATCH_COUNT=${TACHY_MATCH_COUNT:-0}
fi

# Check Oracle Feature Usage by scraping source text of views/mviews
ALL_VIEWS_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner='CLINICAL_ADMIN';" "system" 2>/dev/null)
ALL_MVIEWS_TEXT=$(oracle_query_raw "SELECT query FROM dba_mviews WHERE owner='CLINICAL_ADMIN';" "system" 2>/dev/null)
COMBINED_TEXT="$ALL_VIEWS_TEXT $ALL_MVIEWS_TEXT"

if echo "$COMBINED_TEXT" | grep -qiE "JSON_TABLE"; then JSON_TABLE_USED=true; fi
if echo "$COMBINED_TEXT" | grep -qiE "IGNORE NULLS"; then IGNORE_NULLS_USED=true; fi
if echo "$COMBINED_TEXT" | grep -qiE "MATCH_RECOGNIZE"; then MATCH_RECOGNIZE_USED=true; fi

# Check CSV export
CSV_PATH="/home/ga/Documents/exports/tachycardia_alerts.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS=true
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
fi

# Get GUI Evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# Generate JSON Report
TEMP_JSON=$(mktemp /tmp/icu_telemetry_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "parsed_vitals_exists": $PARSED_VITALS_EXISTS,
    "clean_vitals_exists": $CLEAN_VITALS_EXISTS,
    "hypoglycemia_exists": $HYPOGLYCEMIA_EXISTS,
    "tachycardia_exists": $TACHYCARDIA_EXISTS,
    "json_table_used": $JSON_TABLE_USED,
    "ignore_nulls_used": $IGNORE_NULLS_USED,
    "match_recognize_used": $MATCH_RECOGNIZE_USED,
    "hypo_match_count": $HYPO_MATCH_COUNT,
    "tachy_match_count": $TACHY_MATCH_COUNT,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    $GUI_EVIDENCE
}
EOF

# Ensure secure transfer
rm -f /tmp/icu_telemetry_result.json 2>/dev/null || sudo rm -f /tmp/icu_telemetry_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/icu_telemetry_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/icu_telemetry_result.json
chmod 666 /tmp/icu_telemetry_result.json 2>/dev/null || sudo chmod 666 /tmp/icu_telemetry_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/icu_telemetry_result.json