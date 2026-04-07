#!/bin/bash
# Export script for Waste Landfill EOL task
source /workspace/scripts/task_utils.sh

echo "=== Exporting Waste Landfill EOL Result ==="

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Get Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# 3. Check CSV Output
CSV_FILE="/home/ga/LCA_Results/landfill_eol_results.csv"
CSV_EXISTS="false"
CSV_SIZE=0
CSV_CREATED_DURING_TASK="false"
CSV_CONTENT_VALID="false"

if [ -f "$CSV_FILE" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_FILE")
    FILE_MTIME=$(stat -c %Y "$CSV_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi

    # Check content for keywords
    if grep -qi "Global Warming\|GWP\|CO2\|warming" "$CSV_FILE" && grep -q "[0-9]" "$CSV_FILE"; then
        CSV_CONTENT_VALID="true"
    fi
fi

# 4. Check Database Content (via Derby)
# We need to find the active database
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
# Find the most recently modified database directory
ACTIVE_DB=$(ls -td "$DB_DIR"/*/ 2>/dev/null | head -1)

DB_STATS="{}"
WASTE_FLOW_FOUND="false"
PRODUCT_SYSTEM_FOUND="false"
IMPACT_METHODS_FOUND="false"

if [ -n "$ACTIVE_DB" ]; then
    echo "Checking database at: $ACTIVE_DB"
    
    # Close OpenLCA to unlock Derby DB (safer for querying)
    close_openlca
    sleep 3
    
    # Query: Count Product Systems
    PS_COUNT=$(derby_count "$ACTIVE_DB" "PRODUCT_SYSTEMS")
    if [ "$PS_COUNT" -gt "0" ]; then
        PRODUCT_SYSTEM_FOUND="true"
    fi

    # Query: Check for Waste Flows
    # TBL_FLOWS usually has a FLOW_TYPE column. 
    # Validating specifically for a flow named like "HDPE" or "Waste"
    # We'll dump names of flows created recently or just look for the name
    FLOW_QUERY="SELECT NAME, FLOW_TYPE FROM TBL_FLOWS WHERE LOWER(NAME) LIKE '%hdpe%' OR LOWER(NAME) LIKE '%waste%';"
    FLOW_RESULT=$(derby_query "$ACTIVE_DB" "$FLOW_QUERY")
    
    if echo "$FLOW_RESULT" | grep -qi "HDPE\|Waste"; then
        WASTE_FLOW_FOUND="true"
    fi
    
    # Query: Check LCIA Methods
    METHOD_COUNT=$(derby_count "$ACTIVE_DB" "IMPACT_METHODS")
    if [ "$METHOD_COUNT" -gt "0" ]; then
        IMPACT_METHODS_FOUND="true"
    fi
    
    DB_STATS="{\"ps_count\": $PS_COUNT, \"method_count\": $METHOD_COUNT, \"flow_check\": \"$WASTE_FLOW_FOUND\"}"
fi

# 5. Create JSON Result
cat > /tmp/task_result.json <<EOF
{
  "csv_exists": $CSV_EXISTS,
  "csv_size": $CSV_SIZE,
  "csv_fresh": $CSV_CREATED_DURING_TASK,
  "csv_valid_content": $CSV_CONTENT_VALID,
  "db_found": $([ -n "$ACTIVE_DB" ] && echo "true" || echo "false"),
  "product_system_created": $PRODUCT_SYSTEM_FOUND,
  "waste_flow_created": $WASTE_FLOW_FOUND,
  "lcia_methods_imported": $IMPACT_METHODS_FOUND,
  "task_start": $TASK_START,
  "timestamp": "$CURRENT_TIME"
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json