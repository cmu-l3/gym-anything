#!/bin/bash
echo "=== Exporting international_branch_localization_setup results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final_state.png

# 2. Extract Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Query Location: Berlin Branch
LOC_BERLIN_DATA=$(snipeit_db_query "SELECT id, currency, city FROM locations WHERE name='Berlin Branch' AND deleted_at IS NULL LIMIT 1")
LOC_BERLIN_FOUND="false"
LOC_BERLIN_ID=""
LOC_BERLIN_CUR=""
LOC_BERLIN_CITY=""

if [ -n "$LOC_BERLIN_DATA" ]; then
    LOC_BERLIN_FOUND="true"
    LOC_BERLIN_ID=$(echo "$LOC_BERLIN_DATA" | awk -F'\t' '{print $1}')
    LOC_BERLIN_CUR=$(echo "$LOC_BERLIN_DATA" | awk -F'\t' '{print $2}')
    LOC_BERLIN_CITY=$(echo "$LOC_BERLIN_DATA" | awk -F'\t' '{print $3}')
fi

# 4. Query Supplier: Berlin Tech Wholesale
SUP_BERLIN_DATA=$(snipeit_db_query "SELECT id, city FROM suppliers WHERE name='Berlin Tech Wholesale' AND deleted_at IS NULL LIMIT 1")
SUP_BERLIN_FOUND="false"
SUP_BERLIN_ID=""
SUP_BERLIN_CITY=""

if [ -n "$SUP_BERLIN_DATA" ]; then
    SUP_BERLIN_FOUND="true"
    SUP_BERLIN_ID=$(echo "$SUP_BERLIN_DATA" | awk -F'\t' '{print $1}')
    SUP_BERLIN_CITY=$(echo "$SUP_BERLIN_DATA" | awk -F'\t' '{print $2}')
fi

# 5. Query User: Klaus Weber (kweber)
USER_DATA=$(snipeit_db_query "SELECT id, jobtitle, location_id, UNIX_TIMESTAMP(updated_at) FROM users WHERE username='kweber' AND deleted_at IS NULL LIMIT 1")
USER_FOUND="false"
USER_ID=""
USER_TITLE=""
USER_LOC_ID=""
USER_UPDATED="0"
USER_UPDATED_AFTER="false"

if [ -n "$USER_DATA" ]; then
    USER_FOUND="true"
    USER_ID=$(echo "$USER_DATA" | awk -F'\t' '{print $1}')
    USER_TITLE=$(echo "$USER_DATA" | awk -F'\t' '{print $2}')
    USER_LOC_ID=$(echo "$USER_DATA" | awk -F'\t' '{print $3}')
    USER_UPDATED=$(echo "$USER_DATA" | awk -F'\t' '{print $4}')
    if [ "$USER_UPDATED" -gt "$TASK_START" ]; then
        USER_UPDATED_AFTER="true"
    fi
fi

# 6. Query Existing Asset: ASSET-MAC-088
MAC_DATA=$(snipeit_db_query "SELECT id, rtd_location_id, assigned_to, UNIX_TIMESTAMP(updated_at) FROM assets WHERE asset_tag='ASSET-MAC-088' AND deleted_at IS NULL LIMIT 1")
MAC_FOUND="false"
MAC_ID=""
MAC_LOC_ID=""
MAC_ASSIGNED_TO=""
MAC_UPDATED="0"
MAC_UPDATED_AFTER="false"

if [ -n "$MAC_DATA" ]; then
    MAC_FOUND="true"
    MAC_ID=$(echo "$MAC_DATA" | awk -F'\t' '{print $1}')
    MAC_LOC_ID=$(echo "$MAC_DATA" | awk -F'\t' '{print $2}')
    MAC_ASSIGNED_TO=$(echo "$MAC_DATA" | awk -F'\t' '{print $3}')
    MAC_UPDATED=$(echo "$MAC_DATA" | awk -F'\t' '{print $4}')
    if [ "$MAC_UPDATED" -gt "$TASK_START" ]; then
        MAC_UPDATED_AFTER="true"
    fi
fi

# 7. Query New Model: HP Color LaserJet Pro M479fdw
MDL_PRN_DATA=$(snipeit_db_query "SELECT id, category_id, manufacturer_id FROM models WHERE name='HP Color LaserJet Pro M479fdw' AND deleted_at IS NULL LIMIT 1")
MDL_PRN_FOUND="false"
MDL_PRN_ID=""

if [ -n "$MDL_PRN_DATA" ]; then
    MDL_PRN_FOUND="true"
    MDL_PRN_ID=$(echo "$MDL_PRN_DATA" | awk -F'\t' '{print $1}')
fi

# 8. Query New Asset: ASSET-BER-PRN-01
PRN_DATA=$(snipeit_db_query "SELECT id, model_id, rtd_location_id, supplier_id, purchase_cost FROM assets WHERE asset_tag='ASSET-BER-PRN-01' AND deleted_at IS NULL LIMIT 1")
PRN_FOUND="false"
PRN_ID=""
PRN_MDL_ID=""
PRN_LOC_ID=""
PRN_SUP_ID=""
PRN_COST=""

if [ -n "$PRN_DATA" ]; then
    PRN_FOUND="true"
    PRN_ID=$(echo "$PRN_DATA" | awk -F'\t' '{print $1}')
    PRN_MDL_ID=$(echo "$PRN_DATA" | awk -F'\t' '{print $2}')
    PRN_LOC_ID=$(echo "$PRN_DATA" | awk -F'\t' '{print $3}')
    PRN_SUP_ID=$(echo "$PRN_DATA" | awk -F'\t' '{print $4}')
    PRN_COST=$(echo "$PRN_DATA" | awk -F'\t' '{print $5}')
fi

# Build result JSON
RESULT_JSON=$(cat << JSONEOF
{
  "task_start_time": $TASK_START,
  "location": {
    "found": $LOC_BERLIN_FOUND,
    "id": "$LOC_BERLIN_ID",
    "currency": "$(json_escape "$LOC_BERLIN_CUR")",
    "city": "$(json_escape "$LOC_BERLIN_CITY")"
  },
  "supplier": {
    "found": $SUP_BERLIN_FOUND,
    "id": "$SUP_BERLIN_ID",
    "city": "$(json_escape "$SUP_BERLIN_CITY")"
  },
  "user": {
    "found": $USER_FOUND,
    "id": "$USER_ID",
    "jobtitle": "$(json_escape "$USER_TITLE")",
    "location_id": "$USER_LOC_ID",
    "updated_after_start": $USER_UPDATED_AFTER
  },
  "asset_mac": {
    "found": $MAC_FOUND,
    "id": "$MAC_ID",
    "location_id": "$MAC_LOC_ID",
    "assigned_to": "$MAC_ASSIGNED_TO",
    "updated_after_start": $MAC_UPDATED_AFTER
  },
  "model_prn": {
    "found": $MDL_PRN_FOUND,
    "id": "$MDL_PRN_ID"
  },
  "asset_prn": {
    "found": $PRN_FOUND,
    "id": "$PRN_ID",
    "model_id": "$PRN_MDL_ID",
    "location_id": "$PRN_LOC_ID",
    "supplier_id": "$PRN_SUP_ID",
    "cost": "$PRN_COST"
  }
}
JSONEOF
)

safe_write_result "/tmp/localization_task_result.json" "$RESULT_JSON"
echo "Export complete. Result:"
cat /tmp/localization_task_result.json