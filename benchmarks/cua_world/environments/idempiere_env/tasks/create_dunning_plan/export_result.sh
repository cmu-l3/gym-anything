#!/bin/bash
set -e
echo "=== Exporting create_dunning_plan result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Parameters
CLIENT_ID=$(get_gardenworld_client_id)
TARGET_NAME="Standard Collections"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Checking for Dunning Plan: '$TARGET_NAME' in Client $CLIENT_ID"

# Initialize variables
PLAN_FOUND="false"
PLAN_ID="0"
IS_SEQUENTIAL="N"
LEVEL_COUNT="0"
LEVELS_JSON="[]"
CREATED_TIMESTAMP="0"

# 1. Check Header
PLAN_DATA=$(idempiere_query "SELECT c_dunning_id, createlevelssequentially, created FROM c_dunning WHERE name='$TARGET_NAME' AND ad_client_id=$CLIENT_ID LIMIT 1" 2>/dev/null)

if [ -n "$PLAN_DATA" ]; then
    PLAN_FOUND="true"
    PLAN_ID=$(echo "$PLAN_DATA" | cut -d'|' -f1)
    IS_SEQUENTIAL=$(echo "$PLAN_DATA" | cut -d'|' -f2)
    CREATED_STR=$(echo "$PLAN_DATA" | cut -d'|' -f3)
    
    # Convert created string to timestamp if possible (simple heuristic)
    # Postgres timestamp format: 2023-10-27 10:00:00
    CREATED_TIMESTAMP=$(date -d "$CREATED_STR" +%s 2>/dev/null || echo "0")
    
    echo "  Found Plan ID: $PLAN_ID"
    echo "  Sequential: $IS_SEQUENTIAL"
    
    # 2. Check Levels if header exists
    # We retrieve details for all levels associated with this plan
    # Fields: daysafterdue, daysbetweendunning, chargefee, interestpercent
    # Note: chargefee is tricky because it links to C_Charge or is a direct amount depending on version/config. 
    # In standard iDempiere, 'chargefee' is often an amount on the level or linked via C_Charge.
    # We will query the columns directly present on C_DunningLevel.
    
    # Let's try to query the columns. If chargefee is a direct column:
    LEVEL_ROWS=$(idempiere_query "SELECT daysafterdue, daysbetweendunning, chargefee, interestpercent FROM c_dunninglevel WHERE c_dunning_id=$PLAN_ID AND isactive='Y' ORDER BY daysafterdue ASC" 2>/dev/null || echo "")
    
    # Check row count
    LEVEL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_dunninglevel WHERE c_dunning_id=$PLAN_ID AND isactive='Y'" 2>/dev/null || echo "0")
    
    # Construct JSON array for levels manually to avoid complex dependencies
    # Output format: [{"days_after": 30, "days_between": 0, "fee": 0, "interest": 0}, ...]
    
    LEVELS_JSON="["
    FIRST="true"
    
    # Read line by line
    while IFS= read -r line; do
        if [ -z "$line" ]; then continue; fi
        
        # Split by pipe (psql default separator in helper is usually pipe or we assume handled by helper)
        # The helper `idempiere_query` uses `psql -A -t` which uses pipe `|` as separator by default
        
        DAYS_AFTER=$(echo "$line" | cut -d'|' -f1)
        DAYS_BETWEEN=$(echo "$line" | cut -d'|' -f2)
        FEE=$(echo "$line" | cut -d'|' -f3)
        INTEREST=$(echo "$line" | cut -d'|' -f4)
        
        # Handle nulls/empties
        [ -z "$DAYS_AFTER" ] && DAYS_AFTER="0"
        [ -z "$DAYS_BETWEEN" ] && DAYS_BETWEEN="0"
        [ -z "$FEE" ] && FEE="0"
        [ -z "$INTEREST" ] && INTEREST="0"
        
        if [ "$FIRST" = "true" ]; then
            FIRST="false"
        else
            LEVELS_JSON="$LEVELS_JSON, "
        fi
        
        LEVELS_JSON="$LEVELS_JSON{\"days_after\": $DAYS_AFTER, \"days_between\": $DAYS_BETWEEN, \"fee\": $FEE, \"interest\": $INTEREST}"
        
    done <<< "$LEVEL_ROWS"
    
    LEVELS_JSON="$LEVELS_JSON]"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START_TIME,
    "plan_found": $PLAN_FOUND,
    "plan_created_timestamp": $CREATED_TIMESTAMP,
    "is_sequential": "$IS_SEQUENTIAL",
    "level_count": $LEVEL_COUNT,
    "levels": $LEVELS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="