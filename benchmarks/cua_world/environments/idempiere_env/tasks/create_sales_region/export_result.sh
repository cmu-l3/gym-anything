#!/bin/bash
echo "=== Exporting create_sales_region results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Client ID for queries
CLIENT_ID=$(get_gardenworld_client_id)
if [ -z "$CLIENT_ID" ]; then CLIENT_ID=11; fi

# ----------------------------------------------------------------
# 1. Query Database for Results
# ----------------------------------------------------------------

# Check for the Sales Region 'PNW'
# Format: ID|Name|Description|IsActive
REGION_DATA=$(idempiere_query "SELECT c_salesregion_id, name, description, isactive FROM c_salesregion WHERE value='PNW' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "")

REGION_FOUND="false"
REGION_ID=""
REGION_NAME=""
REGION_DESC=""
REGION_ACTIVE=""

if [ -n "$REGION_DATA" ]; then
    REGION_FOUND="true"
    REGION_ID=$(echo "$REGION_DATA" | cut -d'|' -f1)
    REGION_NAME=$(echo "$REGION_DATA" | cut -d'|' -f2)
    REGION_DESC=$(echo "$REGION_DATA" | cut -d'|' -f3)
    REGION_ACTIVE=$(echo "$REGION_DATA" | cut -d'|' -f4)
fi

# Check Joe Block's assignment
# Get the assigned sales region ID for Joe Block
BP_REGION_ID=$(idempiere_query "SELECT c_salesregion_id FROM c_bpartner WHERE name='Joe Block' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "")

BP_ASSIGNMENT_CORRECT="false"
if [ -n "$REGION_ID" ] && [ "$BP_REGION_ID" == "$REGION_ID" ]; then
    BP_ASSIGNMENT_CORRECT="true"
fi

# Check timestamps to ensure creation happened during task
# We check the 'created' timestamp of the region
REGION_CREATED_TS=""
CREATED_DURING_TASK="false"
if [ -n "$REGION_ID" ]; then
    # PostgreSQL timestamp to epoch
    REGION_CREATED_TS=$(idempiere_query "SELECT EXTRACT(EPOCH FROM created)::int FROM c_salesregion WHERE c_salesregion_id=$REGION_ID" 2>/dev/null || echo "0")
    
    if [ "$REGION_CREATED_TS" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# ----------------------------------------------------------------
# 2. Capture Visual Evidence
# ----------------------------------------------------------------
take_screenshot /tmp/task_final.png

# ----------------------------------------------------------------
# 3. Create JSON Result
# ----------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "region_found": $REGION_FOUND,
    "region_name": "$REGION_NAME",
    "region_desc": "$REGION_DESC",
    "region_active": "$REGION_ACTIVE",
    "bp_assignment_correct": $BP_ASSIGNMENT_CORRECT,
    "created_during_task": $CREATED_DURING_TASK,
    "bp_region_id": "$BP_REGION_ID",
    "new_region_id": "$REGION_ID"
}
EOF

# Save to public location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="
cat /tmp/task_result.json