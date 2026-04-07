#!/bin/bash
echo "=== Exporting multi_company_asset_segmentation result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Get setting value
FCS_VALUE=$(snipeit_db_query "SELECT full_multiple_companies_support FROM settings WHERE id=1" | tr -d '[:space:]')
if [ -z "$FCS_VALUE" ]; then FCS_VALUE=0; fi

# 2. Get company IDs
MT_ID=$(snipeit_db_query "SELECT id FROM companies WHERE name='Meridian Technologies' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
MM_ID=$(snipeit_db_query "SELECT id FROM companies WHERE name='Meridian Media' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
MH_ID=$(snipeit_db_query "SELECT id FROM companies WHERE name='Meridian Healthcare' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')

format_id() {
    if [ -z "$1" ] || [ "$1" = "NULL" ]; then echo "null"; else echo "$1"; fi
}

MT_ID_JSON=$(format_id "$MT_ID")
MM_ID_JSON=$(format_id "$MM_ID")
MH_ID_JSON=$(format_id "$MH_ID")

# 3. Get asset company assignments
get_asset_company() {
    local tag="$1"
    local cid=$(snipeit_db_query "SELECT company_id FROM assets WHERE asset_tag='$tag' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
    format_id "$cid"
}

# 4. Check for collateral changes
COLLATERAL_CHANGES=0
snipeit_db_query "SELECT id, COALESCE(company_id, 0) FROM assets WHERE asset_tag NOT IN ('ASSET-MT001', 'ASSET-MT002', 'ASSET-MT003', 'ASSET-MM001', 'ASSET-MM002', 'ASSET-MM003', 'ASSET-MH001', 'ASSET-MH002', 'ASSET-MH003') AND deleted_at IS NULL ORDER BY id" > /tmp/current_other_assets_company.txt

if ! cmp -s /tmp/initial_other_assets_company.txt /tmp/current_other_assets_company.txt; then
    COLLATERAL_CHANGES=$(diff /tmp/initial_other_assets_company.txt /tmp/current_other_assets_company.txt | grep "^>" | wc -l)
fi

# 5. Build JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "setting_full_multiple_companies_support": $FCS_VALUE,
  "companies": {
    "Meridian Technologies": $MT_ID_JSON,
    "Meridian Media": $MM_ID_JSON,
    "Meridian Healthcare": $MH_ID_JSON
  },
  "assets": {
    "ASSET-MT001": $(get_asset_company "ASSET-MT001"),
    "ASSET-MT002": $(get_asset_company "ASSET-MT002"),
    "ASSET-MT003": $(get_asset_company "ASSET-MT003"),
    "ASSET-MM001": $(get_asset_company "ASSET-MM001"),
    "ASSET-MM002": $(get_asset_company "ASSET-MM002"),
    "ASSET-MM003": $(get_asset_company "ASSET-MM003"),
    "ASSET-MH001": $(get_asset_company "ASSET-MH001"),
    "ASSET-MH002": $(get_asset_company "ASSET-MH002"),
    "ASSET-MH003": $(get_asset_company "ASSET-MH003")
  },
  "collateral_changes_count": $COLLATERAL_CHANGES,
  "timestamp": $(date +%s)
}
EOF

safe_write_result "/tmp/task_result.json" "$(cat "$TEMP_JSON")"
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json