#!/bin/bash
echo "=== Exporting new_site_provisioning results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/provision_final.png

# Read baseline
INITIAL_LOC_COUNT=$(cat /tmp/provision_loc_count.txt 2>/dev/null || echo "0")
INITIAL_DEPT_COUNT=$(cat /tmp/provision_dept_count.txt 2>/dev/null || echo "0")
INITIAL_USER_COUNT=$(cat /tmp/provision_user_count.txt 2>/dev/null || echo "0")
D001_INITIAL_LOC=$(cat /tmp/provision_d001_loc.txt 2>/dev/null || echo "0")
D002_INITIAL_LOC=$(cat /tmp/provision_d002_loc.txt 2>/dev/null || echo "0")

# ---------------------------------------------------------------
# Check location creation
# ---------------------------------------------------------------
CHICAGO_DATA=$(snipeit_db_query "SELECT id, name, address, city, state, zip, country FROM locations WHERE name LIKE '%Chicago%' AND deleted_at IS NULL LIMIT 1")
CHICAGO_FOUND="false"
CHICAGO_ID=""
CHICAGO_NAME=""
CHICAGO_CITY=""
CHICAGO_STATE=""
CHICAGO_ZIP=""
if [ -n "$CHICAGO_DATA" ]; then
    CHICAGO_FOUND="true"
    CHICAGO_ID=$(echo "$CHICAGO_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    CHICAGO_NAME=$(echo "$CHICAGO_DATA" | awk -F'\t' '{print $2}')
    CHICAGO_CITY=$(echo "$CHICAGO_DATA" | awk -F'\t' '{print $4}')
    CHICAGO_STATE=$(echo "$CHICAGO_DATA" | awk -F'\t' '{print $5}')
    CHICAGO_ZIP=$(echo "$CHICAGO_DATA" | awk -F'\t' '{print $6}')
fi

# ---------------------------------------------------------------
# Check department creation
# ---------------------------------------------------------------
LOGISTICS_DATA=$(snipeit_db_query "SELECT id, name, location_id FROM departments WHERE name='Logistics' AND deleted_at IS NULL LIMIT 1")
LOGISTICS_FOUND="false"
LOGISTICS_ID=""
LOGISTICS_LOC=""
if [ -n "$LOGISTICS_DATA" ]; then
    LOGISTICS_FOUND="true"
    LOGISTICS_ID=$(echo "$LOGISTICS_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    LOGISTICS_LOC=$(echo "$LOGISTICS_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
fi

# Check if department is at Chicago location
DEPT_AT_CHICAGO="false"
if [ "$LOGISTICS_FOUND" = "true" ] && [ -n "$CHICAGO_ID" ] && [ "$LOGISTICS_LOC" = "$CHICAGO_ID" ]; then
    DEPT_AT_CHICAGO="true"
fi

# ---------------------------------------------------------------
# Check user creation
# ---------------------------------------------------------------
TRIVERA_DATA=$(snipeit_db_query "SELECT id, username, first_name, last_name, email, jobtitle, department_id, location_id FROM users WHERE username='trivera' AND deleted_at IS NULL LIMIT 1")
TRIVERA_FOUND="false"
TRIVERA_ID=""
TRIVERA_EMAIL=""
TRIVERA_JOBTITLE=""
TRIVERA_DEPT=""
TRIVERA_LOC=""
if [ -n "$TRIVERA_DATA" ]; then
    TRIVERA_FOUND="true"
    TRIVERA_ID=$(echo "$TRIVERA_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    TRIVERA_EMAIL=$(echo "$TRIVERA_DATA" | awk -F'\t' '{print $5}')
    TRIVERA_JOBTITLE=$(echo "$TRIVERA_DATA" | awk -F'\t' '{print $6}')
    TRIVERA_DEPT=$(echo "$TRIVERA_DATA" | awk -F'\t' '{print $7}' | tr -d '[:space:]')
    TRIVERA_LOC=$(echo "$TRIVERA_DATA" | awk -F'\t' '{print $8}' | tr -d '[:space:]')
fi

# Check if user is at Chicago location
USER_AT_CHICAGO="false"
if [ "$TRIVERA_FOUND" = "true" ] && [ -n "$CHICAGO_ID" ] && [ "$TRIVERA_LOC" = "$CHICAGO_ID" ]; then
    USER_AT_CHICAGO="true"
fi

# ---------------------------------------------------------------
# Check asset transfers
# ---------------------------------------------------------------
D001_CURRENT_LOC=$(snipeit_db_query "SELECT rtd_location_id FROM assets WHERE asset_tag='ASSET-D001' AND deleted_at IS NULL" | tr -d '[:space:]')
D002_CURRENT_LOC=$(snipeit_db_query "SELECT rtd_location_id FROM assets WHERE asset_tag='ASSET-D002' AND deleted_at IS NULL" | tr -d '[:space:]')
D001_NOTES=$(snipeit_db_query "SELECT notes FROM assets WHERE asset_tag='ASSET-D001' AND deleted_at IS NULL" | tr -d '\n')
D002_NOTES=$(snipeit_db_query "SELECT notes FROM assets WHERE asset_tag='ASSET-D002' AND deleted_at IS NULL" | tr -d '\n')

D001_AT_CHICAGO="false"
D002_AT_CHICAGO="false"
if [ -n "$CHICAGO_ID" ]; then
    [ "$D001_CURRENT_LOC" = "$CHICAGO_ID" ] && D001_AT_CHICAGO="true"
    [ "$D002_CURRENT_LOC" = "$CHICAGO_ID" ] && D002_AT_CHICAGO="true"
fi

D001_HAS_NOTE="false"
D002_HAS_NOTE="false"
echo "$D001_NOTES" | grep -qi "chicago\|transferred" && D001_HAS_NOTE="true"
echo "$D002_NOTES" | grep -qi "chicago\|transferred" && D002_HAS_NOTE="true"

# ---------------------------------------------------------------
# Check monitor checkout
# ---------------------------------------------------------------
M002_DATA=$(snipeit_db_query "SELECT assigned_to FROM assets WHERE asset_tag='ASSET-M002' AND deleted_at IS NULL" | tr -d '[:space:]')
M002_CHECKED_OUT_TO_TRIVERA="false"
if [ "$TRIVERA_FOUND" = "true" ] && [ "$M002_DATA" = "$TRIVERA_ID" ]; then
    M002_CHECKED_OUT_TO_TRIVERA="true"
fi

# Check checkout note
M002_ID=$(snipeit_db_query "SELECT id FROM assets WHERE asset_tag='ASSET-M002' AND deleted_at IS NULL" | tr -d '[:space:]')
M002_CHECKOUT_NOTE=$(snipeit_db_query "SELECT note FROM action_logs WHERE item_id=$M002_ID AND item_type LIKE '%Asset%' AND action_type='checkout' ORDER BY id DESC LIMIT 1" | tr -d '\n')
M002_NOTE_CORRECT="false"
echo "$M002_CHECKOUT_NOTE" | grep -qi "chicago\|equipment" && M002_NOTE_CORRECT="true"

# ---------------------------------------------------------------
# Control asset check
# ---------------------------------------------------------------
CONTROL_CHANGED=0
while IFS=$'\t' read -r ctag cloc cassigned; do
    ctag=$(echo "$ctag" | tr -d '[:space:]')
    cloc=$(echo "$cloc" | tr -d '[:space:]')
    cassigned=$(echo "$cassigned" | tr -d '[:space:]')
    if [ -z "$ctag" ]; then continue; fi
    CURR=$(snipeit_db_query "SELECT rtd_location_id, COALESCE(assigned_to,0) FROM assets WHERE asset_tag='$ctag' AND deleted_at IS NULL" 2>/dev/null)
    CURR_LOC=$(echo "$CURR" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
    CURR_ASSIGNED=$(echo "$CURR" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
    if [ "$CURR_LOC" != "$cloc" ]; then
        CONTROL_CHANGED=$((CONTROL_CHANGED + 1))
    fi
done < /tmp/provision_control_baseline.txt

# Current counts
CURRENT_LOC_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM locations WHERE deleted_at IS NULL" | tr -d '[:space:]')
CURRENT_USER_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM users WHERE deleted_at IS NULL" | tr -d '[:space:]')

# Build result JSON
RESULT_JSON=$(cat << JSONEOF
{
  "location": {
    "found": $CHICAGO_FOUND,
    "name": "$(json_escape "$CHICAGO_NAME")",
    "city": "$(json_escape "$CHICAGO_CITY")",
    "state": "$(json_escape "$CHICAGO_STATE")",
    "zip": "$(json_escape "$CHICAGO_ZIP")"
  },
  "department": {
    "found": $LOGISTICS_FOUND,
    "at_chicago": $DEPT_AT_CHICAGO
  },
  "user": {
    "found": $TRIVERA_FOUND,
    "email": "$(json_escape "$TRIVERA_EMAIL")",
    "jobtitle": "$(json_escape "$TRIVERA_JOBTITLE")",
    "at_chicago": $USER_AT_CHICAGO,
    "department_id": "$TRIVERA_DEPT"
  },
  "asset_transfers": {
    "d001_at_chicago": $D001_AT_CHICAGO,
    "d002_at_chicago": $D002_AT_CHICAGO,
    "d001_has_note": $D001_HAS_NOTE,
    "d002_has_note": $D002_HAS_NOTE
  },
  "monitor_checkout": {
    "checked_out_to_trivera": $M002_CHECKED_OUT_TO_TRIVERA,
    "checkout_note_correct": $M002_NOTE_CORRECT
  },
  "control_assets_changed": $CONTROL_CHANGED,
  "initial_location_count": $INITIAL_LOC_COUNT,
  "current_location_count": $CURRENT_LOC_COUNT
}
JSONEOF
)

safe_write_result "/tmp/new_site_provisioning_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/new_site_provisioning_result.json"
echo "$RESULT_JSON"
echo "=== new_site_provisioning export complete ==="
