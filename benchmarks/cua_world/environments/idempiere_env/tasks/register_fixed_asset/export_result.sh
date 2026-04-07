#!/bin/bash
set -e
echo "=== Exporting register_fixed_asset results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_asset_count.txt 2>/dev/null || echo "0")

# 3. Query the database for the asset
# We look for the specific Search Key defined in the task
TARGET_KEY="TRUCK-2024-001"
CLIENT_ID=$(get_gardenworld_client_id)
if [ -z "$CLIENT_ID" ]; then CLIENT_ID=11; fi

echo "Querying for asset: $TARGET_KEY in Client $CLIENT_ID"

# Fetch details using psql inside docker
# Returns: Count|Name|Description|GroupID|InServiceDate|LifeYears|LifeMonths|IsActive|CreatedTimestamp
ASSET_DATA=$(idempiere_query "SELECT count(*), name, description, a_asset_group_id, assetservicedate, uselifeyears, uselifemonths, isactive, created FROM a_asset WHERE value='$TARGET_KEY' AND ad_client_id=$CLIENT_ID ORDER BY created DESC LIMIT 1" 2>/dev/null)

# Parse the pipe-separated output (psql -A -t uses | by default)
# Note: idempiere_query uses -A -t. If fields are empty, they appear as ||.
# We need to handle potential empty fields carefully.

# Postgres created timestamp format example: 2024-05-20 10:00:00.123
# We convert it to epoch for comparison

if [ -n "$ASSET_DATA" ]; then
    # Split string by pipe
    IFS='|' read -r COUNT NAME DESCRIPTION GROUP_ID SERVICE_DATE LIFE_YEARS LIFE_MONTHS IS_ACTIVE CREATED_STR <<< "$ASSET_DATA"
    
    # Check if record exists
    if [ "$COUNT" -gt 0 ]; then
        RECORD_FOUND="true"
        
        # Convert created timestamp to epoch
        # CREATED_STR might be "2024-05-20 10:00:00"
        CREATED_EPOCH=$(date -d "$CREATED_STR" +%s 2>/dev/null || echo "0")
        
        if [ "$CREATED_EPOCH" -gt "$TASK_START" ]; then
            CREATED_DURING_TASK="true"
        else
            CREATED_DURING_TASK="false"
        fi
    else
        RECORD_FOUND="false"
        CREATED_DURING_TASK="false"
    fi
else
    RECORD_FOUND="false"
    CREATED_DURING_TASK="false"
fi

# Get current total count
CURRENT_COUNT=$(idempiere_query "SELECT COUNT(*) FROM a_asset WHERE ad_client_id=$CLIENT_ID AND isactive='Y'" 2>/dev/null || echo "0")

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "record_found": $RECORD_FOUND,
    "created_during_task": $CREATED_DURING_TASK,
    "search_key": "$TARGET_KEY",
    "name": "$(echo "$NAME" | sed 's/"/\\"/g')",
    "description": "$(echo "$DESCRIPTION" | sed 's/"/\\"/g')",
    "group_id_present": $(if [ -n "$GROUP_ID" ] && [ "$GROUP_ID" != "0" ]; then echo "true"; else echo "false"; fi),
    "service_date": "$SERVICE_DATE",
    "life_years": "${LIFE_YEARS:-0}",
    "life_months": "${LIFE_MONTHS:-0}",
    "is_active": "$IS_ACTIVE",
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="
cat /tmp/task_result.json