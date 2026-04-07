#!/bin/bash
echo "=== Exporting Logistics Carbon Budget Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final State
take_screenshot /tmp/task_final.png

# 2. File Verification
RESULT_CSV="/home/ga/LCA_Results/optimized_result.csv"
DISTANCE_TXT="/home/ga/LCA_Results/max_distance.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check CSV
CSV_EXISTS="false"
CSV_CONTENT=""
if [ -f "$RESULT_CSV" ]; then
    CSV_MTIME=$(stat -c %Y "$RESULT_CSV" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_EXISTS="true"
        # Read first few lines for GWP check
        CSV_CONTENT=$(head -n 20 "$RESULT_CSV" | base64 -w 0)
    fi
fi

# Check TXT
TXT_EXISTS="false"
TXT_VALUE=""
if [ -f "$DISTANCE_TXT" ]; then
    TXT_MTIME=$(stat -c %Y "$DISTANCE_TXT" 2>/dev/null || echo "0")
    if [ "$TXT_MTIME" -gt "$TASK_START" ]; then
        TXT_EXISTS="true"
        TXT_VALUE=$(cat "$DISTANCE_TXT" | grep -oE "[0-9]+(\.[0-9]+)?")
    fi
fi

# 3. Database Verification (Derby Queries)
# We need to find the active database first
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
# Find most recently modified database
ACTIVE_DB=$(ls -td "$DB_DIR"/*/ 2>/dev/null | head -1)

PARAM_FOUND="false"
PARAM_VALUE="0"
PROCESS_FOUND="false"
EXCHANGE_FORMULA_FOUND="false"

if [ -n "$ACTIVE_DB" ]; then
    echo "Querying database: $ACTIVE_DB"
    
    # Check for 'distance_km' parameter
    # TBL_PARAMETERS columns: ID, NAME, VALUE, ...
    PARAM_QUERY="SELECT NAME, VALUE FROM TBL_PARAMETERS WHERE NAME = 'distance_km'"
    PARAM_RES=$(derby_query "$ACTIVE_DB" "$PARAM_QUERY")
    if echo "$PARAM_RES" | grep -q "distance_km"; then
        PARAM_FOUND="true"
        # Extract value (roughly)
        PARAM_VALUE=$(echo "$PARAM_RES" | grep "distance_km" | awk '{print $2}' | tr -d ' ')
    fi

    # Check for Process creation
    # TBL_PROCESSES: NAME
    PROCESS_QUERY="SELECT NAME FROM TBL_PROCESSES WHERE NAME LIKE '%Distribution Leg%'"
    PROCESS_RES=$(derby_query "$ACTIVE_DB" "$PROCESS_QUERY")
    if echo "$PROCESS_RES" | grep -q "Distribution Leg"; then
        PROCESS_FOUND="true"
    fi

    # Check for Formula usage in Exchanges
    # TBL_EXCHANGES: AMOUNT_FORMULA
    FORMULA_QUERY="SELECT AMOUNT_FORMULA FROM TBL_EXCHANGES WHERE AMOUNT_FORMULA LIKE '%distance_km%'"
    FORMULA_RES=$(derby_query "$ACTIVE_DB" "$FORMULA_QUERY")
    if echo "$FORMULA_RES" | grep -q "distance_km"; then
        EXCHANGE_FORMULA_FOUND="true"
    fi
fi

# 4. App State
APP_RUNNING=$(pgrep -f "openLCA\|openlca" > /dev/null && echo "true" || echo "false")

# 5. Create JSON Result
export_json_result "/tmp/task_result.json" <<EOF
{
  "csv_exists": $CSV_EXISTS,
  "csv_content_b64": "$CSV_CONTENT",
  "txt_exists": $TXT_EXISTS,
  "txt_value": "$TXT_VALUE",
  "param_found": $PARAM_FOUND,
  "param_value": "$PARAM_VALUE",
  "process_found": $PROCESS_FOUND,
  "exchange_formula_found": $EXCHANGE_FORMULA_FOUND,
  "app_running": $APP_RUNNING,
  "screenshot_path": "/tmp/task_final.png"
}
EOF

cat /tmp/task_result.json
echo "=== Export Complete ==="