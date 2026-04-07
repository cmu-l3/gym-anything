#!/bin/bash
echo "=== Exporting eol_disposal_certificate_upload results ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/eol_disposal_final.png

# 1. Check Status Label "Destroyed - Verified"
LABEL_DATA=$(snipeit_db_query "SELECT id, type FROM status_labels WHERE name='Destroyed - Verified' AND deleted_at IS NULL LIMIT 1")
LABEL_ID=""
LABEL_TYPE=""
LABEL_EXISTS="false"

if [ -n "$LABEL_DATA" ]; then
    LABEL_EXISTS="true"
    LABEL_ID=$(echo "$LABEL_DATA" | awk -F'\t' '{print $1}')
    LABEL_TYPE=$(echo "$LABEL_DATA" | awk -F'\t' '{print $2}')
fi

# 2. Function to get asset details and file uploads
get_asset_details() {
    local tag="$1"
    local asset_id=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='$tag' AND deleted_at IS NULL" | tr -d '[:space:]')
    
    if [ -z "$asset_id" ]; then
        echo "{\"tag\":\"$tag\", \"found\":false}"
        return
    fi
    
    local status_id=$(snipeit_db_query "SELECT status_id FROM assets WHERE id=$asset_id" | tr -d '[:space:]')
    local status_name=$(snipeit_db_query "SELECT name FROM status_labels WHERE id=$status_id" | tr -d '\n')
    
    # Check for file uploads in action_logs. 
    # Snipe-IT logs file uploads with action_type='uploaded'
    local upload_count=$(snipeit_db_query "SELECT COUNT(*) FROM action_logs WHERE item_id=$asset_id AND item_type='App\\\\Models\\\\Asset' AND action_type='uploaded'" | tr -d '[:space:]')
    
    local has_file="false"
    if [ "$upload_count" -gt 0 ]; then
        has_file="true"
    fi
    
    echo "{\"tag\":\"$tag\", \"found\":true, \"status_name\":\"$(json_escape "$status_name")\", \"has_file\":$has_file}"
}

# 3. Retrieve details for all 5 assets
HD1_JSON=$(get_asset_details "HD-DISP-001")
HD2_JSON=$(get_asset_details "HD-DISP-002")
HD3_JSON=$(get_asset_details "HD-DISP-003")
HD4_JSON=$(get_asset_details "HD-DISP-004")
HD5_JSON=$(get_asset_details "HD-DISP-005")

# 4. Count unintended status changes (assets moved to the new label that shouldn't be)
UNINTENDED_CHANGES=0
if [ -n "$LABEL_ID" ]; then
    TOTAL_WITH_LABEL=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE status_id=$LABEL_ID AND deleted_at IS NULL" | tr -d '[:space:]')
    TARGETS_WITH_LABEL=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE status_id=$LABEL_ID AND asset_tag IN ('HD-DISP-001','HD-DISP-002','HD-DISP-003','HD-DISP-004') AND deleted_at IS NULL" | tr -d '[:space:]')
    UNINTENDED_CHANGES=$((TOTAL_WITH_LABEL - TARGETS_WITH_LABEL))
fi

# 5. Compile into Result JSON
RESULT_JSON=$(cat << JSONEOF
{
  "status_label": {
    "exists": $LABEL_EXISTS,
    "type": "$(json_escape "$LABEL_TYPE")"
  },
  "assets": {
    "HD-DISP-001": $HD1_JSON,
    "HD-DISP-002": $HD2_JSON,
    "HD-DISP-003": $HD3_JSON,
    "HD-DISP-004": $HD4_JSON,
    "HD-DISP-005": $HD5_JSON
  },
  "unintended_changes": $UNINTENDED_CHANGES
}
JSONEOF
)

safe_write_result "/tmp/eol_disposal_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/eol_disposal_result.json"
echo "$RESULT_JSON"
echo "=== eol_disposal_certificate_upload export complete ==="