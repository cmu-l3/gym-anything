#!/bin/bash
# Export script for Characterize Novel GHG Flow task
# This script runs INSIDE the container after the agent finishes.
# It queries the Derby database and collects file evidence.

source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Results ==="

# 1. Basic Metadata
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
FINAL_SCREENSHOT="/tmp/task_final.png"

# Take final screenshot
take_screenshot "$FINAL_SCREENSHOT"

# 2. Check Output File (CSV Result)
OUTPUT_FILE="/home/ga/LCA_Results/hfc_impact_result.csv"
OUTPUT_EXISTS="false"
OUTPUT_SIZE=0
OUTPUT_CREATED_DURING_TASK="false"
OUTPUT_CONTAINS_VALUE="false"

if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        OUTPUT_CREATED_DURING_TASK="true"
    fi

    # Check for target value "2300" or scientific notation "2.3E3"
    if grep -q "2300\|2\.300\|2\.3E3" "$OUTPUT_FILE"; then
        OUTPUT_CONTAINS_VALUE="true"
    fi
fi

# 3. Database Verification (Derby Queries)
# We need to find the active database first
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
MAX_SIZE=0

# Find largest/most recent database
for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    current_size=$(du -sm "$db_path" 2>/dev/null | cut -f1)
    if [ "${current_size:-0}" -gt "$MAX_SIZE" ]; then
        MAX_SIZE="${current_size:-0}"
        ACTIVE_DB="$db_path"
    fi
done

# Initialize DB findings
DB_FOUND="false"
FLOW_FOUND="false"
METHOD_FOUND="false"
FACTOR_FOUND="false"
FACTOR_VALUE=""

if [ -n "$ACTIVE_DB" ]; then
    DB_FOUND="true"
    echo " querying database: $ACTIVE_DB"
    
    # Close OpenLCA to unlock Derby DB for querying
    close_openlca
    sleep 2

    # A. Check for Flow 'HFC-Experimental'
    # Query returns ID if found
    FLOW_QUERY="SELECT ID FROM TBL_FLOWS WHERE NAME = 'HFC-Experimental'"
    FLOW_ID_RAW=$(derby_query "$ACTIVE_DB" "$FLOW_QUERY")
    # Extract just the numeric ID from ij output
    FLOW_ID=$(echo "$FLOW_ID_RAW" | grep -oP '^\s*\K\d+' | head -1 || echo "")
    
    if [ -n "$FLOW_ID" ]; then
        FLOW_FOUND="true"
        echo "  Flow ID found: $FLOW_ID"
    fi

    # B. Check for Method 'TRACI 2.1 Expanded' (or similar)
    METHOD_QUERY="SELECT ID FROM TBL_IMPACT_METHODS WHERE NAME LIKE '%Expanded%' OR NAME LIKE '%TRACI%'"
    METHOD_IDS_RAW=$(derby_query "$ACTIVE_DB" "$METHOD_QUERY")
    
    # We might get multiple methods, check them
    METHOD_FOUND="false"
    # Iterate through potential method IDs to find the one with our factor
    # This is a bit complex in bash+derby, so we'll try a join query
    
    if [ -n "$FLOW_ID" ]; then
        # C. Check for Characterization Factor
        # Join: ImpactFactor -> ImpactCategory -> ImpactMethod
        # We check if our Flow ID is linked to any category named like 'Global Warming' 
        # with a value ~2300
        
        FACTOR_QUERY="SELECT F.VALUE FROM TBL_IMPACT_FACTORS F \
            JOIN TBL_IMPACT_CATEGORIES C ON F.F_IMPACT_CATEGORY = C.ID \
            WHERE F.F_FLOW = $FLOW_ID \
            AND (C.NAME LIKE '%Global Warming%' OR C.NAME LIKE '%Climate Change%') \
            AND F.VALUE > 2299 AND F.VALUE < 2301"
            
        FACTOR_RESULT=$(derby_query "$ACTIVE_DB" "$FACTOR_QUERY")
        
        # Check if we got a value back
        if echo "$FACTOR_RESULT" | grep -q "2300"; then
            FACTOR_FOUND="true"
            FACTOR_VALUE="2300"
            METHOD_FOUND="true" # Implied if we found the factor in a category
            echo "  Factor 2300 found linked to flow"
        fi
        
        # Fallback: Check if method exists even if factor is wrong (partial credit logic)
        if [ "$METHOD_FOUND" = "false" ]; then
             if echo "$METHOD_IDS_RAW" | grep -q "row selected"; then
                METHOD_FOUND="true"
             fi
        fi
    fi
fi

# 4. JSON Export
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "output_size": $OUTPUT_SIZE,
    "output_created_during_task": $OUTPUT_CREATED_DURING_TASK,
    "output_contains_value": $OUTPUT_CONTAINS_VALUE,
    "db_found": $DB_FOUND,
    "db_path": "$ACTIVE_DB",
    "flow_found": $FLOW_FOUND,
    "method_found": $METHOD_FOUND,
    "factor_found": $FACTOR_FOUND,
    "factor_value": "$FACTOR_VALUE",
    "screenshot_path": "$FINAL_SCREENSHOT"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="