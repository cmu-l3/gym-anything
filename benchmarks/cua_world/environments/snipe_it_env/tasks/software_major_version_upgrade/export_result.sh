#!/bin/bash
echo "=== Exporting software_major_version_upgrade results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Load baselines
TARGET_MAYA_USERS=$(cat /tmp/target_maya_users.txt 2>/dev/null || echo "")
TARGET_C4D_USERS=$(cat /tmp/target_c4d_users.txt 2>/dev/null || echo "")
LEGACY_MAYA_ID=$(cat /tmp/legacy_maya_id.txt 2>/dev/null || echo "0")
LEGACY_C4D_ID=$(cat /tmp/legacy_c4d_id.txt 2>/dev/null || echo "0")

# 1. Fetch Legacy License States
LEGACY_MAYA_NAME=$(snipeit_db_query "SELECT name FROM licenses WHERE id=$LEGACY_MAYA_ID" | tr -d '\n')
LEGACY_MAYA_CHECKED_OUT=$(snipeit_db_query "SELECT COUNT(*) FROM license_seats WHERE license_id=$LEGACY_MAYA_ID AND assigned_to IS NOT NULL" | tr -d '[:space:]')

LEGACY_C4D_NAME=$(snipeit_db_query "SELECT name FROM licenses WHERE id=$LEGACY_C4D_ID" | tr -d '\n')
LEGACY_C4D_CHECKED_OUT=$(snipeit_db_query "SELECT COUNT(*) FROM license_seats WHERE license_id=$LEGACY_C4D_ID AND assigned_to IS NOT NULL" | tr -d '[:space:]')

# 2. Fetch New Maya License State
NEW_MAYA_DATA=$(snipeit_db_query "SELECT id, seats, purchase_cost, product_key FROM licenses WHERE name='Autodesk Maya 2025' AND deleted_at IS NULL LIMIT 1")
NEW_MAYA_ID=$(echo "$NEW_MAYA_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
if [ -n "$NEW_MAYA_ID" ]; then
    NEW_MAYA_FOUND="true"
    NEW_MAYA_SEATS=$(echo "$NEW_MAYA_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
    NEW_MAYA_COST=$(echo "$NEW_MAYA_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
    NEW_MAYA_KEY=$(echo "$NEW_MAYA_DATA" | awk -F'\t' '{print $4}' | tr -d '\n')
    
    # Get who holds the seats
    NEW_MAYA_USERS=$(snipeit_db_query "SELECT assigned_to FROM license_seats WHERE license_id=$NEW_MAYA_ID AND assigned_to IS NOT NULL" | tr '\n' ',' | sed 's/,$//')
else
    NEW_MAYA_FOUND="false"
    NEW_MAYA_SEATS="0"
    NEW_MAYA_COST="0"
    NEW_MAYA_KEY=""
    NEW_MAYA_USERS=""
fi

# 3. Fetch New C4D License State
NEW_C4D_DATA=$(snipeit_db_query "SELECT id, seats, purchase_cost, product_key FROM licenses WHERE name='Maxon Cinema 4D 2024' AND deleted_at IS NULL LIMIT 1")
NEW_C4D_ID=$(echo "$NEW_C4D_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
if [ -n "$NEW_C4D_ID" ]; then
    NEW_C4D_FOUND="true"
    NEW_C4D_SEATS=$(echo "$NEW_C4D_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
    NEW_C4D_COST=$(echo "$NEW_C4D_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
    NEW_C4D_KEY=$(echo "$NEW_C4D_DATA" | awk -F'\t' '{print $4}' | tr -d '\n')
    
    # Get who holds the seats
    NEW_C4D_USERS=$(snipeit_db_query "SELECT assigned_to FROM license_seats WHERE license_id=$NEW_C4D_ID AND assigned_to IS NOT NULL" | tr '\n' ',' | sed 's/,$//')
else
    NEW_C4D_FOUND="false"
    NEW_C4D_SEATS="0"
    NEW_C4D_COST="0"
    NEW_C4D_KEY=""
    NEW_C4D_USERS=""
fi

# 4. Build JSON Result
RESULT_JSON=$(cat << JSONEOF
{
  "target_maya_users": "${TARGET_MAYA_USERS}",
  "target_c4d_users": "${TARGET_C4D_USERS}",
  "legacy_maya": {
    "name": "$(json_escape "$LEGACY_MAYA_NAME")",
    "checked_out_seats": ${LEGACY_MAYA_CHECKED_OUT:-0}
  },
  "legacy_c4d": {
    "name": "$(json_escape "$LEGACY_C4D_NAME")",
    "checked_out_seats": ${LEGACY_C4D_CHECKED_OUT:-0}
  },
  "new_maya": {
    "found": ${NEW_MAYA_FOUND},
    "seats": ${NEW_MAYA_SEATS:-0},
    "cost": ${NEW_MAYA_COST:-0},
    "key": "$(json_escape "$NEW_MAYA_KEY")",
    "assigned_users": "${NEW_MAYA_USERS}"
  },
  "new_c4d": {
    "found": ${NEW_C4D_FOUND},
    "seats": ${NEW_C4D_SEATS:-0},
    "cost": ${NEW_C4D_COST:-0},
    "key": "$(json_escape "$NEW_C4D_KEY")",
    "assigned_users": "${NEW_C4D_USERS}"
  }
}
JSONEOF
)

safe_write_result "/tmp/software_major_version_upgrade_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/software_major_version_upgrade_result.json"
cat "/tmp/software_major_version_upgrade_result.json"
echo "=== Export complete ==="