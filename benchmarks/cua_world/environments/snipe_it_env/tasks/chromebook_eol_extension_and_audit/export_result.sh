#!/bin/bash
echo "=== Exporting chromebook_eol_extension_and_audit results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/chromebook_eol_final.png

# 1. Fetch Depreciation Schedule
DEP_DATA=$(snipeit_db_query "SELECT id, months FROM depreciations WHERE name='Chromebook 4-Year' AND deleted_at IS NULL LIMIT 1")
DEP_FOUND="false"
DEP_ID="0"
DEP_MONTHS="0"
if [ -n "$DEP_DATA" ]; then
    DEP_FOUND="true"
    DEP_ID=$(echo "$DEP_DATA" | awk -F'\t' '{print $1}')
    DEP_MONTHS=$(echo "$DEP_DATA" | awk -F'\t' '{print $2}')
fi

# 2. Fetch Model Data
MOD_DATA=$(snipeit_db_query "SELECT eol, depreciation_id FROM models WHERE name='Lenovo Chromebook 300e' AND deleted_at IS NULL LIMIT 1")
MOD_FOUND="false"
MOD_EOL="0"
MOD_DEP_ID="0"
if [ -n "$MOD_DATA" ]; then
    MOD_FOUND="true"
    MOD_EOL=$(echo "$MOD_DATA" | awk -F'\t' '{print $1}')
    MOD_DEP_ID=$(echo "$MOD_DATA" | awk -F'\t' '{print $2}')
fi

# 3. Fetch Asset Status and Notes
build_asset_json() {
    local tag="$1"
    local data=$(snipeit_db_query "SELECT sl.name, a.notes FROM assets a LEFT JOIN status_labels sl ON a.status_id = sl.id WHERE a.asset_tag='$tag' AND a.deleted_at IS NULL LIMIT 1")
    if [ -z "$data" ]; then
        echo "{\"tag\": \"$tag\", \"found\": false}"
        return
    fi
    local status=$(echo "$data" | awk -F'\t' '{print $1}')
    local notes=$(echo "$data" | awk -F'\t' '{print $2}')
    echo "{\"tag\": \"$tag\", \"found\": true, \"status\": \"$(json_escape "$status")\", \"notes\": \"$(json_escape "$notes")\"}"
}

CB001=$(build_asset_json "ASSET-CB001")
CB002=$(build_asset_json "ASSET-CB002")
CB003=$(build_asset_json "ASSET-CB003")
CB004=$(build_asset_json "ASSET-CB004")
CB005=$(build_asset_json "ASSET-CB005")
CB006=$(build_asset_json "ASSET-CB006")

# 4. Create Result JSON
RESULT_JSON=$(cat << JSONEOF
{
  "depreciation": {
    "found": $DEP_FOUND,
    "id": "$DEP_ID",
    "months": "$DEP_MONTHS"
  },
  "model": {
    "found": $MOD_FOUND,
    "eol": "$MOD_EOL",
    "depreciation_id": "$MOD_DEP_ID"
  },
  "assets": {
    "CB001": $CB001,
    "CB002": $CB002,
    "CB003": $CB003,
    "CB004": $CB004,
    "CB005": $CB005,
    "CB006": $CB006
  }
}
JSONEOF
)

safe_write_result "/tmp/chromebook_audit_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/chromebook_audit_result.json"
echo "$RESULT_JSON"
echo "=== Export Complete ==="