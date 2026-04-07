#!/bin/bash
echo "=== Exporting aviation_tool_calibration_certification results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Build JSON array of asset states
RESULT_JSON="{\"assets\": ["

FIRST=true
for i in {1..6}; do
    TAG="ASSET-CAL-00$i"
    
    # Get raw basic data from DB
    ASSET_DATA=$(snipeit_db_query "SELECT id, status_id, notes FROM assets WHERE asset_tag='$TAG' AND deleted_at IS NULL LIMIT 1")
    if [ -z "$ASSET_DATA" ]; then continue; fi
    
    ASSET_ID=$(echo "$ASSET_DATA" | awk -F'\t' '{print $1}')
    STATUS_ID=$(echo "$ASSET_DATA" | awk -F'\t' '{print $2}')
    NOTES=$(echo "$ASSET_DATA" | awk -F'\t' '{print $3}')
    
    STATUS_NAME=$(snipeit_db_query "SELECT name FROM status_labels WHERE id=$STATUS_ID" | tr -d '\n')
    
    # Get custom fields reliably via API
    API_RESP=$(snipeit_api GET "hardware/${ASSET_ID}")
    
    # Parse custom field "Next Calibration Date". Checking both possible structures.
    CAL_DATE=$(echo "$API_RESP" | jq -r '.custom_fields | to_entries | .[]? | select(.key=="Next Calibration Date" or .value.field=="Next Calibration Date") | .value.value // ""')
    
    # Get uploaded files from action_logs for this asset
    UPLOADED_FILES=$(snipeit_db_query "SELECT filename FROM action_logs WHERE item_type='App\\\\Models\\\\Asset' AND action_type='uploaded' AND item_id=${ASSET_ID}" | tr '\n' ',' | sed 's/,$//')
    
    if [ "$FIRST" = true ]; then FIRST=false; else RESULT_JSON+=","; fi
    
    RESULT_JSON+=$(cat <<EOF
    {
      "tag": "$TAG",
      "id": $ASSET_ID,
      "status": "$(json_escape "$STATUS_NAME")",
      "notes": "$(json_escape "$NOTES")",
      "cal_date": "$(json_escape "$CAL_DATE")",
      "uploaded_files": "$(json_escape "$UPLOADED_FILES")"
    }
EOF
)
done

RESULT_JSON+="]}"

safe_write_result "/tmp/calibration_result.json" "$RESULT_JSON"

echo "Export complete. Result saved to /tmp/calibration_result.json"
cat /tmp/calibration_result.json