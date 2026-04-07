#!/bin/bash
# Export results for Aircraft Cascading Delay Analysis task
echo "=== Exporting Cascading Delay Analysis Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png ga

# Sanitize integer outputs
sanitize_int() { local val="$1"; if [[ "$val" =~ ^[0-9]+$ ]]; then echo "$val"; else echo "0"; fi; }

# Initialize checks
ITINERARY_VW_EXISTS=false
WINDOW_FUNCTIONS_USED=false
AMPLIFIERS_VW_EXISTS=false
AMPLIFIERS_COUNT=0
STATS_VW_EXISTS=false
STATS_COUNT=0
SNOWBALL_VW_EXISTS=false
SNOWBALL_COUNT=0
MATCH_RECOGNIZE_USED=false
CSV_EXISTS=false
CSV_SIZE=0

# Extract view definitions safely by moving LONG text to a LOB in a temp table
oracle_query_raw "BEGIN EXECUTE IMMEDIATE 'DROP TABLE temp_view_text'; EXCEPTION WHEN OTHERS THEN NULL; END;" "flight_ops" "Flights2024"
oracle_query_raw "CREATE TABLE temp_view_text AS SELECT view_name, TO_LOB(text) AS view_text FROM user_views;" "flight_ops" "Flights2024"

# 1. Check AIRCRAFT_ITINERARY_VW
VW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM user_views WHERE view_name = 'AIRCRAFT_ITINERARY_VW';" "flight_ops" "Flights2024" | tr -d '[:space:]')
if [ "${VW_CHECK:-0}" -gt 0 ]; then
    ITINERARY_VW_EXISTS=true
    
    # Check for Window functions (LAG/LEAD)
    W_CHK=$(oracle_query_raw "SELECT COUNT(*) FROM temp_view_text WHERE view_name = 'AIRCRAFT_ITINERARY_VW' AND (UPPER(view_text) LIKE '%LAG(%' OR UPPER(view_text) LIKE '%LEAD(%');" "flight_ops" "Flights2024" | tr -d '[:space:]')
    if [ "${W_CHK:-0}" -gt 0 ]; then
        WINDOW_FUNCTIONS_USED=true
    fi
fi

# 2. Check DELAY_AMPLIFIERS_VW
AMP_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM user_views WHERE view_name = 'DELAY_AMPLIFIERS_VW';" "flight_ops" "Flights2024" | tr -d '[:space:]')
if [ "${AMP_CHECK:-0}" -gt 0 ]; then
    AMPLIFIERS_VW_EXISTS=true
    ACNT=$(oracle_query_raw "SELECT COUNT(*) FROM DELAY_AMPLIFIERS_VW;" "flight_ops" "Flights2024" | tr -d '[:space:]')
    AMPLIFIERS_COUNT=$(sanitize_int "$ACNT")
fi

# 3. Check AIRPORT_PERFORMANCE_STATS_VW
STAT_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM user_views WHERE view_name = 'AIRPORT_PERFORMANCE_STATS_VW';" "flight_ops" "Flights2024" | tr -d '[:space:]')
if [ "${STAT_CHECK:-0}" -gt 0 ]; then
    STATS_VW_EXISTS=true
    SCNT=$(oracle_query_raw "SELECT COUNT(*) FROM AIRPORT_PERFORMANCE_STATS_VW;" "flight_ops" "Flights2024" | tr -d '[:space:]')
    STATS_COUNT=$(sanitize_int "$SCNT")
fi

# 4. Check SNOWBALL_DELAYS_VW
SNO_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM user_views WHERE view_name = 'SNOWBALL_DELAYS_VW';" "flight_ops" "Flights2024" | tr -d '[:space:]')
if [ "${SNO_CHECK:-0}" -gt 0 ]; then
    SNOWBALL_VW_EXISTS=true
    
    # Check row count
    SNO_CNT=$(oracle_query_raw "SELECT COUNT(*) FROM SNOWBALL_DELAYS_VW;" "flight_ops" "Flights2024" | tr -d '[:space:]')
    SNOWBALL_COUNT=$(sanitize_int "$SNO_CNT")
    
    # Check for MATCH_RECOGNIZE
    MR_CHK=$(oracle_query_raw "SELECT COUNT(*) FROM temp_view_text WHERE view_name = 'SNOWBALL_DELAYS_VW' AND UPPER(view_text) LIKE '%MATCH_RECOGNIZE%';" "flight_ops" "Flights2024" | tr -d '[:space:]')
    if [ "${MR_CHK:-0}" -gt 0 ]; then
        MATCH_RECOGNIZE_USED=true
    fi
fi

# Clean up temp view text table
oracle_query_raw "DROP TABLE temp_view_text;" "flight_ops" "Flights2024"

# 5. Check CSV export
CSV_PATH="/home/ga/Documents/exports/airport_delay_scorecard.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS=true
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
fi

# Collect GUI interaction evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# Create final JSON
TEMP_JSON=$(mktemp /tmp/flight_ops_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "itinerary_vw_exists": $ITINERARY_VW_EXISTS,
    "window_functions_used": $WINDOW_FUNCTIONS_USED,
    "amplifiers_vw_exists": $AMPLIFIERS_VW_EXISTS,
    "amplifiers_count": $AMPLIFIERS_COUNT,
    "stats_vw_exists": $STATS_VW_EXISTS,
    "stats_count": $STATS_COUNT,
    "snowball_vw_exists": $SNOWBALL_VW_EXISTS,
    "snowball_count": $SNOWBALL_COUNT,
    "match_recognize_used": $MATCH_RECOGNIZE_USED,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    ${GUI_EVIDENCE}
}
EOF

# Ensure safe move and permissions
rm -f /tmp/flight_ops_result.json 2>/dev/null || sudo rm -f /tmp/flight_ops_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/flight_ops_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/flight_ops_result.json
chmod 666 /tmp/flight_ops_result.json 2>/dev/null || sudo chmod 666 /tmp/flight_ops_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results successfully exported."
cat /tmp/flight_ops_result.json
echo "=== Export Complete ==="