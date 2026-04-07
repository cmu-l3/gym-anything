#!/bin/bash
echo "=== Exporting location_hierarchy_setup results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/location_hierarchy_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
STAGING_ID=$(cat /tmp/staging_location_id.txt 2>/dev/null || echo "0")

# ---------------------------------------------------------------
# 1. Check Parent Location
# ---------------------------------------------------------------
PARENT_DATA=$(snipeit_db_query "SELECT id, name, address, city, state, zip, country, manager_id, UNIX_TIMESTAMP(created_at) FROM locations WHERE name='West Campus Medical Center' AND deleted_at IS NULL LIMIT 1")

PARENT_FOUND="false"
PARENT_ID="0"
PARENT_ADDRESS=""
PARENT_CITY=""
PARENT_STATE=""
PARENT_ZIP=""
PARENT_COUNTRY=""
PARENT_MANAGER_ID="0"
PARENT_CREATED_AT="0"
MANAGER_USERNAME=""

if [ -n "$PARENT_DATA" ]; then
    PARENT_FOUND="true"
    PARENT_ID=$(echo "$PARENT_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    PARENT_ADDRESS=$(echo "$PARENT_DATA" | awk -F'\t' '{print $3}')
    PARENT_CITY=$(echo "$PARENT_DATA" | awk -F'\t' '{print $4}')
    PARENT_STATE=$(echo "$PARENT_DATA" | awk -F'\t' '{print $5}')
    PARENT_ZIP=$(echo "$PARENT_DATA" | awk -F'\t' '{print $6}')
    PARENT_COUNTRY=$(echo "$PARENT_DATA" | awk -F'\t' '{print $7}')
    PARENT_MANAGER_ID=$(echo "$PARENT_DATA" | awk -F'\t' '{print $8}' | tr -d '[:space:]')
    PARENT_CREATED_AT=$(echo "$PARENT_DATA" | awk -F'\t' '{print $9}' | tr -d '[:space:]')
    
    # Get manager username if assigned
    if [ -n "$PARENT_MANAGER_ID" ] && [ "$PARENT_MANAGER_ID" != "NULL" ]; then
        MANAGER_USERNAME=$(snipeit_db_query "SELECT username FROM users WHERE id=$PARENT_MANAGER_ID LIMIT 1" | tr -d '[:space:]')
    fi
fi

# ---------------------------------------------------------------
# 2. Check Child Locations
# ---------------------------------------------------------------
CHILD_COUNT=0
CHILD_NAMES="[]"

if [ "$PARENT_FOUND" = "true" ] && [ -n "$PARENT_ID" ]; then
    CHILD_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM locations WHERE parent_id=$PARENT_ID AND deleted_at IS NULL" | tr -d '[:space:]')
    
    # Get all child names into JSON array
    CHILDREN=$(snipeit_db_query "SELECT name FROM locations WHERE parent_id=$PARENT_ID AND deleted_at IS NULL")
    if [ -n "$CHILDREN" ]; then
        CHILD_NAMES="["
        first=true
        while IFS= read -r cname; do
            if [ "$first" = true ]; then first=false; else CHILD_NAMES+=","; fi
            CHILD_NAMES+="\"$(json_escape "$cname")\""
        done <<< "$CHILDREN"
        CHILD_NAMES+="]"
    fi
fi

# ---------------------------------------------------------------
# 3. Check Asset Relocations
# ---------------------------------------------------------------
build_asset_json() {
    local tag="$1"
    local data=$(snipeit_db_query "SELECT a.rtd_location_id, l.name FROM assets a LEFT JOIN locations l ON a.rtd_location_id = l.id WHERE a.asset_tag='$tag' AND a.deleted_at IS NULL LIMIT 1")
    if [ -z "$data" ]; then
        echo "{\"tag\": \"$tag\", \"found\": false}"
        return
    fi
    local loc_id=$(echo "$data" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    local loc_name=$(echo "$data" | awk -F'\t' '{print $2}')
    echo "{\"tag\": \"$tag\", \"found\": true, \"location_id\": \"$loc_id\", \"location_name\": \"$(json_escape "$loc_name")\"}"
}

A1_JSON=$(build_asset_json "ASSET-WC01")
A2_JSON=$(build_asset_json "ASSET-WC02")
A3_JSON=$(build_asset_json "ASSET-WC03")
A4_JSON=$(build_asset_json "ASSET-WC04")

# ---------------------------------------------------------------
# 4. Check if Staging Warehouse is Empty
# ---------------------------------------------------------------
REMAINING_STAGED_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE rtd_location_id=$STAGING_ID AND deleted_at IS NULL" | tr -d '[:space:]')

# ---------------------------------------------------------------
# 5. Build Result JSON
# ---------------------------------------------------------------
RESULT_JSON=$(cat << JSONEOF
{
  "task_start_time": $TASK_START,
  "parent": {
    "found": $PARENT_FOUND,
    "created_at": "$PARENT_CREATED_AT",
    "address": "$(json_escape "$PARENT_ADDRESS")",
    "city": "$(json_escape "$PARENT_CITY")",
    "state": "$(json_escape "$PARENT_STATE")",
    "zip": "$(json_escape "$PARENT_ZIP")",
    "country": "$(json_escape "$PARENT_COUNTRY")",
    "manager_username": "$(json_escape "$MANAGER_USERNAME")"
  },
  "children": {
    "count": $CHILD_COUNT,
    "names": $CHILD_NAMES
  },
  "assets": {
    "WC01": $A1_JSON,
    "WC02": $A2_JSON,
    "WC03": $A3_JSON,
    "WC04": $A4_JSON
  },
  "staging_warehouse": {
    "id": $STAGING_ID,
    "remaining_assets": $REMAINING_STAGED_COUNT
  }
}
JSONEOF
)

safe_write_result "/tmp/location_hierarchy_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/location_hierarchy_result.json"
echo "$RESULT_JSON"
echo "=== location_hierarchy_setup export complete ==="