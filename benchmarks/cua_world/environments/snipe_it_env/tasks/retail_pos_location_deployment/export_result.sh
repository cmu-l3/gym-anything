#!/bin/bash
echo "=== Exporting retail_pos_location_deployment results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check Chicago Location
LOC_CHI_DATA=$(snipeit_db_query "SELECT id, address FROM locations WHERE name LIKE '%Store #42%' OR name LIKE '%Chicago%' LIMIT 1")
if [ -n "$LOC_CHI_DATA" ]; then
    LOC_CHI_ID=$(echo "$LOC_CHI_DATA" | awk -F'\t' '{print $1}')
    LOC_CHI_ADDR=$(echo "$LOC_CHI_DATA" | awk -F'\t' '{print $2}')
else
    LOC_CHI_ID="null"
    LOC_CHI_ADDR=""
fi

# Chicago Assets Assignment
CHI_ASSETS_JSON="["
first="true"
for tag in "POS-TERM-042" "POS-SCAN-042" "POS-PRNT-042" "POS-PAY-042"; do
    data=$(snipeit_db_query "SELECT assigned_to, assigned_type FROM assets WHERE asset_tag='$tag'")
    if [ -n "$data" ]; then
        assigned_to=$(echo "$data" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
        assigned_type=$(echo "$data" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
        if [ "$assigned_to" = "NULL" ] || [ -z "$assigned_to" ]; then assigned_to="null"; fi
    else
        assigned_to="null"
        assigned_type=""
    fi
    if [ "$first" = "true" ]; then first="false"; else CHI_ASSETS_JSON+=","; fi
    CHI_ASSETS_JSON+="{\"tag\": \"$tag\", \"assigned_to\": $assigned_to, \"assigned_type\": \"$(json_escape "$assigned_type")\"}"
done
CHI_ASSETS_JSON+="]"

# Miami Location ID
LOC_MIA_ID=$(snipeit_db_query "SELECT id FROM locations WHERE name='Store #18 - Miami' LIMIT 1" | tr -d '[:space:]')
if [ -z "$LOC_MIA_ID" ]; then LOC_MIA_ID="null"; fi

# Miami Printer 018
MIA18_DATA=$(snipeit_db_query "SELECT assigned_to, assigned_type, status_id FROM assets WHERE asset_tag='POS-PRNT-018'")
if [ -n "$MIA18_DATA" ]; then
    MIA18_ASSIGNED_TO=$(echo "$MIA18_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    MIA18_ASSIGNED_TYPE=$(echo "$MIA18_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
    MIA18_STATUS_ID=$(echo "$MIA18_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
    MIA18_STATUS_NAME=$(snipeit_db_query "SELECT name FROM status_labels WHERE id=$MIA18_STATUS_ID" | tr -d '\n')
    if [ "$MIA18_ASSIGNED_TO" = "NULL" ] || [ -z "$MIA18_ASSIGNED_TO" ]; then MIA18_ASSIGNED_TO="null"; fi
else
    MIA18_ASSIGNED_TO="null"
    MIA18_ASSIGNED_TYPE=""
    MIA18_STATUS_NAME=""
fi

# Spare Printer
SPARE_DATA=$(snipeit_db_query "SELECT assigned_to, assigned_type FROM assets WHERE asset_tag='POS-PRNT-SPARE'")
if [ -n "$SPARE_DATA" ]; then
    SPARE_ASSIGNED_TO=$(echo "$SPARE_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    SPARE_ASSIGNED_TYPE=$(echo "$SPARE_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
    if [ "$SPARE_ASSIGNED_TO" = "NULL" ] || [ -z "$SPARE_ASSIGNED_TO" ]; then SPARE_ASSIGNED_TO="null"; fi
else
    SPARE_ASSIGNED_TO="null"
    SPARE_ASSIGNED_TYPE=""
fi

# Bad users (anti-gaming check)
BAD_USERS_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM users WHERE first_name LIKE '%Store%' OR last_name LIKE '%Store%' OR username LIKE '%Store%'" | tr -d '[:space:]')
if [ -z "$BAD_USERS_COUNT" ]; then BAD_USERS_COUNT=0; fi

RESULT_JSON=$(cat << JSONEOF
{
  "chicago_location_id": ${LOC_CHI_ID},
  "chicago_location_address": "$(json_escape "$LOC_CHI_ADDR")",
  "chicago_assets": ${CHI_ASSETS_JSON},
  "miami_location_id": ${LOC_MIA_ID},
  "printer_018_assigned_to": ${MIA18_ASSIGNED_TO},
  "printer_018_assigned_type": "$(json_escape "$MIA18_ASSIGNED_TYPE")",
  "printer_018_status_name": "$(json_escape "$MIA18_STATUS_NAME")",
  "printer_spare_assigned_to": ${SPARE_ASSIGNED_TO},
  "printer_spare_assigned_type": "$(json_escape "$SPARE_ASSIGNED_TYPE")",
  "bad_users_count": ${BAD_USERS_COUNT}
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
echo "$RESULT_JSON"
echo "=== Export Complete ==="