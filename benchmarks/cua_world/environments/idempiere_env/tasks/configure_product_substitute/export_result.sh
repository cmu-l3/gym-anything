#!/bin/bash
echo "=== Exporting configure_product_substitute results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Get IDs again to be safe
CLIENT_ID=$(get_gardenworld_client_id)
SPADE_ID=$(idempiere_query "SELECT m_product_id FROM m_product WHERE name='Spade' AND ad_client_id=$CLIENT_ID" 2>/dev/null)
HOE_ID=$(idempiere_query "SELECT m_product_id FROM m_product WHERE name='Hoe' AND ad_client_id=$CLIENT_ID" 2>/dev/null)

# 2. Query the M_Substitute table
# We look for a record where Product=Spade and Substitute=Hoe
# created after task start
echo "--- Querying Database for Substitute Record ---"

# Need to handle potential empty result if query fails
RESULT_JSON="{}"

if [ -n "$SPADE_ID" ] && [ -n "$HOE_ID" ]; then
    # Helper to get field value
    get_field() {
        local col=$1
        idempiere_query "SELECT $col FROM m_substitute WHERE m_product_id=$SPADE_ID AND substitute_id=$HOE_ID" 2>/dev/null
    }

    # Check existence
    COUNT=$(idempiere_query "SELECT COUNT(*) FROM m_substitute WHERE m_product_id=$SPADE_ID AND substitute_id=$HOE_ID" 2>/dev/null || echo "0")
    
    if [ "$COUNT" -gt "0" ]; then
        LINK_EXISTS="true"
        NAME=$(get_field "name")
        DESCRIPTION=$(get_field "description")
        CREATED=$(get_field "created")
        
        # Check if created during task (simple string comparison of timestamps or just assume 'new' if it didn't exist before)
        # Since we deleted it in setup, any existence is 'new'
        IS_NEW="true"
    else
        LINK_EXISTS="false"
        NAME=""
        DESCRIPTION=""
        IS_NEW="false"
    fi
else
    LINK_EXISTS="false"
    NAME=""
    DESCRIPTION=""
    IS_NEW="false"
fi

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "link_exists": $LINK_EXISTS,
    "parent_product_id": "$SPADE_ID",
    "substitute_product_id": "$HOE_ID",
    "record_name": "$NAME",
    "record_description": "$DESCRIPTION",
    "is_new_record": $IS_NEW,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="