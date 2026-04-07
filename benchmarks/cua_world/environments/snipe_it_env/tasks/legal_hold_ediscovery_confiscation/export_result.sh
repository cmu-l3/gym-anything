#!/bin/bash
echo "=== Exporting legal_hold_ediscovery_confiscation results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot evidence
take_screenshot /tmp/task_final.png

# Detect "Secure Storage - Legal" Location
LOC_DATA=$(snipeit_db_query "SELECT id, name FROM locations WHERE name LIKE '%Secure Storage - Legal%' AND deleted_at IS NULL LIMIT 1")
LOC_FOUND="false"
LOC_ID="0"
if [ -n "$LOC_DATA" ]; then
    LOC_FOUND="true"
    LOC_ID=$(echo "$LOC_DATA" | awk -F'\t' '{print $1}')
fi

# Detect "Legal Hold" Status Label
STAT_DATA=$(snipeit_db_query "SELECT id, name, type FROM status_labels WHERE name LIKE '%Legal Hold%' AND deleted_at IS NULL LIMIT 1")
STAT_FOUND="false"
STAT_ID="0"
STAT_TYPE=""
if [ -n "$STAT_DATA" ]; then
    STAT_FOUND="true"
    STAT_ID=$(echo "$STAT_DATA" | awk -F'\t' '{print $1}')
    STAT_TYPE=$(echo "$STAT_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
fi

# Helper to capture asset state
build_asset_json() {
    local tag=$1
    local data=$(snipeit_db_query "SELECT assigned_to, status_id, rtd_location_id, notes FROM assets WHERE asset_tag='$tag' AND deleted_at IS NULL LIMIT 1")
    if [ -z "$data" ]; then
        echo "{\"tag\": \"$tag\", \"found\": false}"
        return
    fi
    local assigned=$(echo "$data" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    local status_id=$(echo "$data" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
    local loc_id=$(echo "$data" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
    local notes=$(echo "$data" | awk -F'\t' '{print $4}')
    
    local is_checked_in="true"
    if [ -n "$assigned" ] && [ "$assigned" != "NULL" ] && [ "$assigned" != "0" ]; then
        is_checked_in="false"
    fi
    
    echo "{\"tag\": \"$tag\", \"found\": true, \"is_checked_in\": $is_checked_in, \"status_id\": \"$status_id\", \"loc_id\": \"$loc_id\", \"notes\": \"$(json_escape "$notes")\", \"assigned_to\": \"$assigned\"}"
}

# Fetch status of Target Assets
TARGET_JSON="["
for tag in ASSET-LH01 ASSET-LH02 ASSET-LH03 ASSET-LH04 ASSET-LH05 ASSET-LH06; do
    if [ "$TARGET_JSON" != "[" ]; then TARGET_JSON+=","; fi
    TARGET_JSON+=$(build_asset_json "$tag")
done
TARGET_JSON+="]"

# Fetch status of Distractor Assets
DISTRACTOR_JSON="["
for tag in ASSET-DS01 ASSET-DS02; do
    if [ "$DISTRACTOR_JSON" != "[" ]; then DISTRACTOR_JSON+=","; fi
    DISTRACTOR_JSON+=$(build_asset_json "$tag")
done
DISTRACTOR_JSON+="]"

DISTRACTOR_BASELINE=$(cat /tmp/distractor_baseline.txt 2>/dev/null)

# Structure and save final JSON
RESULT_JSON=$(cat << JSONEOF
{
  "location": {
    "found": $LOC_FOUND,
    "id": "$LOC_ID"
  },
  "status_label": {
    "found": $STAT_FOUND,
    "id": "$STAT_ID",
    "type": "$STAT_TYPE"
  },
  "targets": $TARGET_JSON,
  "distractors": $DISTRACTOR_JSON,
  "distractor_baseline": "$(json_escape "$DISTRACTOR_BASELINE")"
}
JSONEOF
)

safe_write_result "/tmp/legal_hold_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/legal_hold_result.json"
echo "$RESULT_JSON"
echo "=== Export complete ==="