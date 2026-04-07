#!/bin/bash
# Export script for Update LCIA Factors AR6 task

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type close_openlca &>/dev/null; then
    close_openlca() { pkill -f "openLCA\|openlca" 2>/dev/null || true; sleep 3; }
fi

echo "=== Exporting Update LCIA Factors AR6 Result ==="

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png
echo "Final screenshot saved"

# 2. Check for log file
LOG_FILE="/home/ga/LCA_Results/ar6_update_log.txt"
LOG_EXISTS="false"
LOG_CONTENT=""
if [ -f "$LOG_FILE" ]; then
    LOG_EXISTS="true"
    LOG_CONTENT=$(cat "$LOG_FILE" | head -c 500)
    echo "Log file found."
else
    echo "Log file not found."
fi

# 3. Query Derby Database for the updated factors
# We need to verify the values in the database table TBL_IMPACT_FACTORS

# Close OpenLCA to unlock Derby DB
close_openlca
sleep 3

DB_DIR="/home/ga/openLCA-data-1.4/databases"
# Find the largest/active database
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

METHOD_FOUND="false"
METHANE_VALUE=""
N2O_VALUE=""
DB_NAME=""

if [ -n "$ACTIVE_DB" ]; then
    DB_NAME=$(basename "$ACTIVE_DB")
    echo "Querying database: $DB_NAME"
    
    # Check if our specific method exists
    # We look for 'TRACI 2.1 (IPCC AR6 Modified)'
    
    # SQL to find the method and the specific factors
    # Note: Using LIKE for category name to be robust against "Global Warming Air" vs "Global warming"
    SQL_QUERY="
    SELECT 
        fl.NAME as FLOW_NAME, 
        f.VALUE as FACTOR_VALUE
    FROM TBL_IMPACT_FACTORS f
    JOIN TBL_IMPACT_CATEGORIES c ON f.F_IMPACT_CATEGORY = c.ID
    JOIN TBL_IMPACT_METHODS m ON c.F_IMPACT_METHOD = m.ID
    JOIN TBL_FLOWS fl ON f.F_FLOW = fl.ID
    WHERE 
        m.NAME = 'TRACI 2.1 (IPCC AR6 Modified)' 
        AND (c.NAME LIKE '%Global Warming%' OR c.NAME LIKE '%Global warming%')
        AND (fl.NAME = 'Methane' OR fl.NAME = 'Nitrous oxide');
    "
    
    QUERY_RESULT=$(derby_query "$ACTIVE_DB" "$SQL_QUERY")
    
    echo "Derby Query Result:"
    echo "$QUERY_RESULT"
    
    # Parse results
    if echo "$QUERY_RESULT" | grep -q "Methane"; then
        METHOD_FOUND="true"
        # Extract values roughly (grep logic)
        # Expected output format:
        # FLOW_NAME      |FACTOR_VALUE
        # ----------------------------
        # Methane        |29.8
        # Nitrous oxide  |273.0
        
        METHANE_LINE=$(echo "$QUERY_RESULT" | grep "Methane")
        METHANE_VALUE=$(echo "$METHANE_LINE" | awk -F'|' '{print $2}' | xargs)
        
        N2O_LINE=$(echo "$QUERY_RESULT" | grep "Nitrous oxide")
        N2O_VALUE=$(echo "$N2O_LINE" | awk -F'|' '{print $2}' | xargs)
    fi
else
    echo "No active database found to query."
fi

# 4. Check for evidence of method creation in openLCA log
LOG_EVIDENCE="false"
if [ -f "/tmp/openlca_ga.log" ]; then
    if grep -q "ImpactMethod" "/tmp/openlca_ga.log" || grep -q "TRACI 2.1 (IPCC AR6 Modified)" "/tmp/openlca_ga.log"; then
        LOG_EVIDENCE="true"
    fi
fi

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "log_exists": $LOG_EXISTS,
    "log_content": "$(echo "$LOG_CONTENT" | tr -d '"' | tr -d '\n')",
    "method_found_in_db": $METHOD_FOUND,
    "db_methane_value": "$METHANE_VALUE",
    "db_n2o_value": "$N2O_VALUE",
    "openlca_log_evidence": $LOG_EVIDENCE,
    "database_name": "$DB_NAME"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON generated at /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="