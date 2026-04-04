#!/bin/bash
echo "=== Exporting office_closure_asset_transfer results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/transfer_final.png

# Read baseline
LOC_LONDON=$(cat /tmp/transfer_london_id.txt 2>/dev/null || echo "0")
LOC_NYC=$(cat /tmp/transfer_nyc_id.txt 2>/dev/null || echo "0")
INITIAL_LONDON_COUNT=$(cat /tmp/transfer_london_asset_count.txt 2>/dev/null || echo "0")
INITIAL_NYC_COUNT=$(cat /tmp/transfer_nyc_asset_count.txt 2>/dev/null || echo "0")
INITIAL_LONDON_TAGS=$(cat /tmp/transfer_london_tags.txt 2>/dev/null || echo "")
INITIAL_LONDON_CHECKED_OUT=$(cat /tmp/transfer_london_checked_out.txt 2>/dev/null || echo "")

# ---------------------------------------------------------------
# Check current state
# ---------------------------------------------------------------

# How many assets still at London?
REMAINING_LONDON=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE rtd_location_id=$LOC_LONDON AND deleted_at IS NULL" | tr -d '[:space:]')

# Which original London assets are now at NYC?
RELOCATED_TO_NYC=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE rtd_location_id=$LOC_NYC AND deleted_at IS NULL AND asset_tag IN ($(echo "$INITIAL_LONDON_TAGS" | sed "s/\([^,]*\)/'\1'/g"))" 2>/dev/null | tr -d '[:space:]')

# Check each originally-London asset
build_relocated_json() {
    local tag="$1"
    local data=$(snipeit_db_query "SELECT a.asset_tag, a.rtd_location_id, l.name, a.assigned_to, a.notes FROM assets a LEFT JOIN locations l ON a.rtd_location_id=l.id WHERE a.asset_tag='$tag' AND a.deleted_at IS NULL LIMIT 1")
    if [ -z "$data" ]; then
        echo "{\"tag\": \"$tag\", \"found\": false}"
        return
    fi
    local loc_name=$(echo "$data" | awk -F'\t' '{print $3}')
    local assigned=$(echo "$data" | awk -F'\t' '{print $4}' | tr -d '[:space:]')
    local notes=$(echo "$data" | awk -F'\t' '{print $5}')
    local is_checked_in="true"
    if [ -n "$assigned" ] && [ "$assigned" != "NULL" ] && [ "$assigned" != "0" ]; then
        is_checked_in="false"
    fi
    echo "{\"tag\": \"$tag\", \"found\": true, \"location\": \"$(json_escape "$loc_name")\", \"is_checked_in\": $is_checked_in, \"notes\": \"$(json_escape "$notes")\"}"
}

# Build JSON for each originally-London asset
IFS=',' read -ra LONDON_TAGS_ARR <<< "$INITIAL_LONDON_TAGS"
RELOCATED_DETAILS="["
first=true
for tag in "${LONDON_TAGS_ARR[@]}"; do
    tag=$(echo "$tag" | tr -d '[:space:]')
    if [ -z "$tag" ]; then continue; fi
    if [ "$first" = true ]; then first=false; else RELOCATED_DETAILS+=","; fi
    RELOCATED_DETAILS+=$(build_relocated_json "$tag")
done
RELOCATED_DETAILS+="]"

# Check new assets
D004_JSON=$(build_relocated_json "ASSET-D004")
M004_JSON=$(build_relocated_json "ASSET-M004")

# Count how many relocated assets have RELOCATED in notes
RELOCATION_NOTE_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE deleted_at IS NULL AND notes LIKE '%RELOCATED%' AND asset_tag IN ($(echo "$INITIAL_LONDON_TAGS" | sed "s/\([^,]*\)/'\1'/g"))" 2>/dev/null | tr -d '[:space:]')

# Check non-London assets unchanged
NON_LONDON_CHANGED=0
while IFS=$'\t' read -r ntag nloc; do
    ntag=$(echo "$ntag" | tr -d '[:space:]')
    nloc=$(echo "$nloc" | tr -d '[:space:]')
    if [ -z "$ntag" ]; then continue; fi
    CURR_LOC=$(snipeit_db_query "SELECT rtd_location_id FROM assets WHERE asset_tag='$ntag' AND deleted_at IS NULL" 2>/dev/null | tr -d '[:space:]')
    if [ "$CURR_LOC" != "$nloc" ]; then
        NON_LONDON_CHANGED=$((NON_LONDON_CHANGED + 1))
    fi
done < /tmp/transfer_non_london_baseline.txt

# Build result JSON
RESULT_JSON=$(cat << JSONEOF
{
  "initial_london_count": $INITIAL_LONDON_COUNT,
  "initial_nyc_count": $INITIAL_NYC_COUNT,
  "remaining_london_count": $REMAINING_LONDON,
  "relocated_to_nyc_count": $RELOCATED_TO_NYC,
  "relocation_note_count": $RELOCATION_NOTE_COUNT,
  "relocated_assets": $RELOCATED_DETAILS,
  "new_asset_d004": $D004_JSON,
  "new_asset_m004": $M004_JSON,
  "non_london_assets_changed": $NON_LONDON_CHANGED,
  "initial_london_checked_out": "$(json_escape "$INITIAL_LONDON_CHECKED_OUT")"
}
JSONEOF
)

safe_write_result "/tmp/office_closure_asset_transfer_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/office_closure_asset_transfer_result.json"
echo "$RESULT_JSON"
echo "=== office_closure_asset_transfer export complete ==="
