#!/bin/bash
echo "=== Exporting post_acquisition_asset_integration results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Read initial counts
INITIAL_COMPANIES=$(cat /tmp/initial_companies.txt 2>/dev/null || echo "0")
INITIAL_LOCATIONS=$(cat /tmp/initial_locations.txt 2>/dev/null || echo "0")
INITIAL_USERS=$(cat /tmp/initial_users.txt 2>/dev/null || echo "0")
INITIAL_ASSETS=$(cat /tmp/initial_assets.txt 2>/dev/null || echo "0")

# Get companies
TECH_COMPANY_ID=$(snipeit_db_query "SELECT id FROM companies WHERE name='TechVantage Solutions' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')
NOVA_COMPANY_ID=$(snipeit_db_query "SELECT id FROM companies WHERE name='NovaBridge Consulting' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')

# Get location
AUSTIN_LOC_ID=$(snipeit_db_query "SELECT id FROM locations WHERE name LIKE '%Austin%' AND city='Austin' AND deleted_at IS NULL LIMIT 1" | tr -d '[:space:]')

# Helper functions
build_user_json() {
    local username="$1"
    local data=$(snipeit_db_query "SELECT id, company_id FROM users WHERE username='$username' AND deleted_at IS NULL LIMIT 1")
    if [ -z "$data" ]; then
        echo "{\"username\": \"$username\", \"found\": false}"
    else
        local id=$(echo "$data" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
        local company_id=$(echo "$data" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
        echo "{\"username\": \"$username\", \"found\": true, \"id\": \"$id\", \"company_id\": \"$company_id\"}"
    fi
}

build_asset_json() {
    local tag="$1"
    local data=$(snipeit_db_query "SELECT serial, COALESCE(company_id, 0), COALESCE(assigned_to, 0) FROM assets WHERE asset_tag='$tag' AND deleted_at IS NULL LIMIT 1")
    if [ -z "$data" ]; then
        echo "{\"tag\": \"$tag\", \"found\": false}"
    else
        local serial=$(echo "$data" | awk -F'\t' '{print $1}')
        local company_id=$(echo "$data" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
        local assigned_to=$(echo "$data" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
        echo "{\"tag\": \"$tag\", \"found\": true, \"serial\": \"$(json_escape "$serial")\", \"company_id\": \"$company_id\", \"assigned_to\": \"$assigned_to\"}"
    fi
}

# Collect user data
USER_RCHEN=$(build_user_json "rchen")
USER_MWEBB=$(build_user_json "mwebb")
USER_PKAPOOR=$(build_user_json "pkapoor")

# Collect asset data
ASSET_1=$(build_asset_json "NB-001")
ASSET_2=$(build_asset_json "NB-002")
ASSET_3=$(build_asset_json "NB-003")
ASSET_4=$(build_asset_json "NB-004")

# Check collateral damage
if [ -n "$TECH_COMPANY_ID" ]; then
    OTHER_ASSETS_TECH=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE asset_tag NOT IN ('NB-001', 'NB-002', 'NB-003', 'NB-004') AND company_id = $TECH_COMPANY_ID AND deleted_at IS NULL" | tr -d '[:space:]')
else
    OTHER_ASSETS_TECH=0
fi

if [ -n "$NOVA_COMPANY_ID" ]; then
    OTHER_ASSETS_NOVA=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE asset_tag NOT IN ('NB-001', 'NB-002', 'NB-003', 'NB-004') AND company_id = $NOVA_COMPANY_ID AND deleted_at IS NULL" | tr -d '[:space:]')
else
    OTHER_ASSETS_NOVA=0
fi

# Current total asset count
CURRENT_ASSETS=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE deleted_at IS NULL" | tr -d '[:space:]')

# Build result JSON
RESULT_JSON=$(cat << JSONEOF
{
  "tech_company_id": "${TECH_COMPANY_ID}",
  "nova_company_id": "${NOVA_COMPANY_ID}",
  "austin_loc_id": "${AUSTIN_LOC_ID}",
  "users": {
    "rchen": $USER_RCHEN,
    "mwebb": $USER_MWEBB,
    "pkapoor": $USER_PKAPOOR
  },
  "assets": {
    "NB-001": $ASSET_1,
    "NB-002": $ASSET_2,
    "NB-003": $ASSET_3,
    "NB-004": $ASSET_4
  },
  "initial_assets": $INITIAL_ASSETS,
  "current_assets": $CURRENT_ASSETS,
  "other_assets_tech": $OTHER_ASSETS_TECH,
  "other_assets_nova": $OTHER_ASSETS_NOVA
}
JSONEOF
)

safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="