#!/bin/bash
echo "=== Exporting create_discount_schema result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_schema_count.txt 2>/dev/null || echo "0")
TARGET_NAME="Bulk Order Incentive 2024"

# ---------------------------------------------------------------
# 1. Query Database for Schema Header
# ---------------------------------------------------------------
echo "Checking for schema: $TARGET_NAME"

# Get Schema Details
# Format: ID|Name|Description|DiscountType|IsActive|CreatedTimestamp
SCHEMA_DATA=$(idempiere_query "SELECT m_discountschema_id, name, description, discounttype, isactive, created FROM m_discountschema WHERE name='$TARGET_NAME' ORDER BY created DESC LIMIT 1" 2>/dev/null)

SCHEMA_FOUND="false"
SCHEMA_ID=""
SCHEMA_NAME=""
SCHEMA_DESC=""
SCHEMA_TYPE=""
SCHEMA_ACTIVE=""
SCHEMA_CREATED=""

if [ -n "$SCHEMA_DATA" ]; then
    SCHEMA_FOUND="true"
    IFS='|' read -r SCHEMA_ID SCHEMA_NAME SCHEMA_DESC SCHEMA_TYPE SCHEMA_ACTIVE SCHEMA_CREATED <<< "$SCHEMA_DATA"
fi

# ---------------------------------------------------------------
# 2. Query Database for Break Lines
# ---------------------------------------------------------------
BREAKS_JSON="[]"
if [ "$SCHEMA_FOUND" == "true" ]; then
    echo "Schema found (ID: $SCHEMA_ID). Checking break lines..."
    
    # Get breaks: Seq|Qty|Discount|IsActive
    BREAKS_RAW=$(idempiere_query "SELECT seqno, breakvalue, breakdiscount, isactive FROM m_discountschemabreak WHERE m_discountschema_id=$SCHEMA_ID ORDER BY breakvalue ASC" 2>/dev/null)
    
    if [ -n "$BREAKS_RAW" ]; then
        # Convert PSQL output to JSON array
        # Input format: 
        # 10|10.00|5.00|Y
        # 20|25.00|8.00|Y
        
        BREAKS_JSON=$(echo "$BREAKS_RAW" | while IFS='|' read -r seq qty disc active; do
            # Clean up numbers (remove trailing zeros potentially)
            qty=$(echo $qty | sed 's/0*$//;s/\.$//')
            disc=$(echo $disc | sed 's/0*$//;s/\.$//')
            echo "{\"seq\": \"$seq\", \"qty\": \"$qty\", \"discount\": \"$disc\", \"active\": \"$active\"},"
        done | sed '$s/,$//') # remove trailing comma
        BREAKS_JSON="[$BREAKS_JSON]"
    fi
fi

# ---------------------------------------------------------------
# 3. Check System State
# ---------------------------------------------------------------
CURRENT_COUNT=$(idempiere_query "SELECT COUNT(*) FROM m_discountschema" 2>/dev/null || echo "0")
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# ---------------------------------------------------------------
# 4. Generate JSON Result
# ---------------------------------------------------------------
# Use python to robustly create JSON to avoid shell escaping hell
python3 -c "
import json
import sys

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'initial_count': int('$INITIAL_COUNT'),
    'current_count': int('$CURRENT_COUNT'),
    'schema_found': '$SCHEMA_FOUND' == 'true',
    'schema_details': {
        'name': '$SCHEMA_NAME',
        'description': '$SCHEMA_DESC',
        'type': '$SCHEMA_TYPE',
        'active': '$SCHEMA_ACTIVE' == 'Y'
    },
    'breaks': $BREAKS_JSON,
    'app_running': '$APP_RUNNING' == 'true',
    'screenshot_path': '/tmp/task_final.png'
}

print(json.dumps(result, indent=2))
" > /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="