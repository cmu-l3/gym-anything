#!/bin/bash
# Export script for create_device_group task

echo "=== Exporting Create Device Group Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || { echo "Failed to source task_utils"; exit 1; }

# Get task timing
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ==============================================================================
# DATABASE VERIFICATION
# ==============================================================================

# 1. Check if the group exists
# We look for 'DMZ_Servers' (case-insensitive) in the hostgroup table
GROUP_CHECK_SQL="SELECT group_id, groupname, description FROM hostgroup WHERE LOWER(groupname) = 'dmz_servers'"
GROUP_DATA=$(ela_db_query "$GROUP_CHECK_SQL" 2>/dev/null)

GROUP_EXISTS="false"
GROUP_ID=""
GROUP_NAME=""
GROUP_DESC=""

if [ -n "$GROUP_DATA" ] && [ "$GROUP_DATA" != "0 rows" ]; then
    GROUP_EXISTS="true"
    # Parse pipe-separated values: ID|NAME|DESC
    GROUP_ID=$(echo "$GROUP_DATA" | cut -d'|' -f1)
    GROUP_NAME=$(echo "$GROUP_DATA" | cut -d'|' -f2)
    GROUP_DESC=$(echo "$GROUP_DATA" | cut -d'|' -f3)
fi

# 2. Check device membership
# If group exists, check if any device is assigned to it in HostGroupMapping
DEVICE_ASSIGNED="false"
DEVICE_COUNT="0"

if [ "$GROUP_EXISTS" = "true" ] && [ -n "$GROUP_ID" ]; then
    # HostGroupMapping usually links GROUP_ID to HOST_ID
    MEMBER_CHECK_SQL="SELECT count(*) FROM HostGroupMapping WHERE GROUP_ID = $GROUP_ID"
    MEMBER_COUNT=$(ela_db_query "$MEMBER_COUNT_SQL" 2>/dev/null || echo "0")
    
    # Alternative check: join with HostDetails to see if localhost/127.0.0.1 is there
    JOIN_SQL="SELECT count(*) FROM HostGroupMapping m JOIN HostDetails h ON m.HOST_ID = h.HOST_ID WHERE m.GROUP_ID = $GROUP_ID"
    JOIN_COUNT=$(ela_db_query "$JOIN_SQL" 2>/dev/null || echo "0")
    
    if [ "$JOIN_COUNT" -gt 0 ]; then
        DEVICE_ASSIGNED="true"
        DEVICE_COUNT="$JOIN_COUNT"
    fi
fi

# 3. Anti-gaming: Check against initial state
INITIAL_COUNT=$(cat /tmp/initial_group_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(ela_db_query "SELECT count(*) FROM hostgroup" 2>/dev/null || echo "0")

# Logic: Group must exist AND (Count increased OR Group wasn't in initial list)
IS_NEW_GROUP="false"
if [ "$GROUP_EXISTS" = "true" ]; then
    # Check if this specific name was in the initial list
    if ! grep -q -i "DMZ_Servers" /tmp/initial_groups.txt 2>/dev/null; then
        IS_NEW_GROUP="true"
    fi
fi

# ==============================================================================
# SCREENSHOT VERIFICATION
# ==============================================================================
EXPECTED_SCREENSHOT="/tmp/device_group_result.png"
SCREENSHOT_EXISTS="false"
SCREENSHOT_SIZE="0"
SCREENSHOT_CREATED_DURING_TASK="false"

if [ -f "$EXPECTED_SCREENSHOT" ]; then
    SCREENSHOT_EXISTS="true"
    SCREENSHOT_SIZE=$(stat -c %s "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    SCREENSHOT_MTIME=$(stat -c %Y "$EXPECTED_SCREENSHOT" 2>/dev/null || echo "0")
    
    if [ "$SCREENSHOT_MTIME" -gt "$TASK_START" ]; then
        SCREENSHOT_CREATED_DURING_TASK="true"
    fi
fi

# Take a final system screenshot for backup verification
take_screenshot /tmp/task_final_state.png

# ==============================================================================
# JSON EXPORT
# ==============================================================================

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "group_exists": $GROUP_EXISTS,
    "group_name": "$GROUP_NAME",
    "group_description": "$GROUP_DESC",
    "device_assigned": $DEVICE_ASSIGNED,
    "member_count": $DEVICE_COUNT,
    "is_new_group": $IS_NEW_GROUP,
    "initial_group_count": $INITIAL_COUNT,
    "current_group_count": $CURRENT_COUNT,
    "user_screenshot_exists": $SCREENSHOT_EXISTS,
    "user_screenshot_created_during_task": $SCREENSHOT_CREATED_DURING_TASK,
    "final_screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="