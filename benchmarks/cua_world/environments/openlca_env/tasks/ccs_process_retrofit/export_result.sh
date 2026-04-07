#!/bin/bash
# Export script for CCS Process Retrofit task

source /workspace/scripts/task_utils.sh

echo "=== Exporting CCS Retrofit Result ==="

# 1. Capture Final Screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Check Report File
REPORT_PATH="/home/ga/LCA_Results/ccs_retrofit_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_SIZE=0
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

if [ -f "$REPORT_PATH" ]; then
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_EXISTS="true"
        REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
        REPORT_CONTENT=$(cat "$REPORT_PATH" | head -c 1000) # Read first 1000 chars
    fi
fi

# 3. Query Internal Derby Database
# We need to find the database, then query for the CCS process and its CO2 flow.

# Find active database
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
MAX_SIZE=0
for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    DB_SIZE=$(du -sm "$db_path" 2>/dev/null | cut -f1 || echo "0")
    if [ "${DB_SIZE:-0}" -gt "$MAX_SIZE" ]; then
        MAX_SIZE="${DB_SIZE:-0}"
        ACTIVE_DB="$db_path"
    fi
done

# Initialize DB variables
DB_FOUND="false"
PROCESS_COUNT=0
CCS_PROCESS_FOUND="false"
CCS_PROCESS_NAME=""
CCS_PROCESS_DESC=""
CCS_CO2_AMOUNT=""
ORIGINAL_CO2_AMOUNT=""
ORIGINAL_PROCESS_NAME=""

if [ -n "$ACTIVE_DB" ] && [ "${MAX_SIZE:-0}" -gt 5 ]; then
    DB_FOUND="true"
    
    # Close OpenLCA to unlock Derby DB
    close_openlca
    sleep 3
    
    # Query: Count processes
    PROCESS_COUNT=$(derby_count "$ACTIVE_DB" "PROCESSES" 2>/dev/null || echo "0")
    
    # Query: Find CCS Process info
    # Look for name containing 'CCS' or 'Capture'
    QUERY_CCS="SELECT ID, NAME, DESCRIPTION FROM TBL_PROCESSES WHERE (UPPER(NAME) LIKE '%CCS%' OR UPPER(NAME) LIKE '%CAPTURE%') FETCH FIRST 1 ROWS ONLY;"
    CCS_RESULT=$(derby_query "$ACTIVE_DB" "$QUERY_CCS" 2>/dev/null)
    
    # Parse Derby output (simple parsing assuming ID is first numeric)
    # Derby output is messy, we look for the row content
    CCS_ID=$(echo "$CCS_RESULT" | grep -oP '^\s*\K[0-9]+(?=\s+|\|)' | head -1)
    
    if [ -n "$CCS_ID" ]; then
        CCS_PROCESS_FOUND="true"
        # Extract name roughly
        CCS_PROCESS_NAME=$(echo "$CCS_RESULT" | grep "$CCS_ID" | head -1)
        
        # Query: Find CO2 exchange for this process
        # Joining TBL_EXCHANGES and TBL_FLOWS to find Carbon Dioxide output
        # Note: In OpenLCA schema, F_FLOW references TBL_FLOWS.ID
        QUERY_CO2="SELECT e.AMOUNT FROM TBL_EXCHANGES e JOIN TBL_FLOWS f ON e.F_FLOW = f.ID WHERE e.F_OWNER = $CCS_ID AND (UPPER(f.NAME) LIKE '%CARBON DIOXIDE%' OR UPPER(f.NAME) LIKE '%CO2%') AND e.IS_INPUT = 0 FETCH FIRST 1 ROWS ONLY;"
        CO2_RESULT=$(derby_query "$ACTIVE_DB" "$QUERY_CO2" 2>/dev/null)
        CCS_CO2_AMOUNT=$(echo "$CO2_RESULT" | grep -oP '^\s*\K[0-9]+\.?[0-9]*' | head -1)
    fi
    
    # Query: Find an Original Process (Natural Gas Electricity) for baseline comparison
    QUERY_ORIG="SELECT ID, NAME FROM TBL_PROCESSES WHERE UPPER(NAME) LIKE '%ELECTRICITY%' AND UPPER(NAME) LIKE '%NATURAL GAS%' AND UPPER(NAME) NOT LIKE '%CCS%' AND UPPER(NAME) NOT LIKE '%CAPTURE%' FETCH FIRST 1 ROWS ONLY;"
    ORIG_RESULT=$(derby_query "$ACTIVE_DB" "$QUERY_ORIG" 2>/dev/null)
    ORIG_ID=$(echo "$ORIG_RESULT" | grep -oP '^\s*\K[0-9]+(?=\s+|\|)' | head -1)
    
    if [ -n "$ORIG_ID" ]; then
        ORIGINAL_PROCESS_NAME=$(echo "$ORIG_RESULT" | grep "$ORIG_ID" | head -1)
        QUERY_ORIG_CO2="SELECT e.AMOUNT FROM TBL_EXCHANGES e JOIN TBL_FLOWS f ON e.F_FLOW = f.ID WHERE e.F_OWNER = $ORIG_ID AND (UPPER(f.NAME) LIKE '%CARBON DIOXIDE%' OR UPPER(f.NAME) LIKE '%CO2%') AND e.IS_INPUT = 0 FETCH FIRST 1 ROWS ONLY;"
        ORIG_CO2_RESULT=$(derby_query "$ACTIVE_DB" "$QUERY_ORIG_CO2" 2>/dev/null)
        ORIGINAL_CO2_AMOUNT=$(echo "$ORIG_CO2_RESULT" | grep -oP '^\s*\K[0-9]+\.?[0-9]*' | head -1)
    fi
fi

# 4. Construct JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_content_preview": $(echo "$REPORT_CONTENT" | jq -R -s '.'),
    "db_found": $DB_FOUND,
    "process_count": ${PROCESS_COUNT:-0},
    "ccs_process_found": $CCS_PROCESS_FOUND,
    "ccs_process_id": "${CCS_ID:-}",
    "ccs_process_raw_name": $(echo "$CCS_PROCESS_NAME" | jq -R -s '.'),
    "ccs_co2_amount": "${CCS_CO2_AMOUNT:-}",
    "original_process_id": "${ORIG_ID:-}",
    "original_process_raw_name": $(echo "$ORIGINAL_PROCESS_NAME" | jq -R -s '.'),
    "original_co2_amount": "${ORIGINAL_CO2_AMOUNT:-}",
    "active_db_path": "$ACTIVE_DB",
    "timestamp": $(date +%s)
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result JSON generated at /tmp/task_result.json"
cat /tmp/task_result.json