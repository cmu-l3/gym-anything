#!/bin/bash
echo "=== Exporting update_registered_weapon_color result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database for the specific weapon by Serial Number
# This allows us to verify the specific record targeted in the instructions
SERIAL="SM-9981"

# Get Weapon Details
WEAPON_DATA=$(opencad_db_query "SELECT id, name_id, weapon_color, weapon_name FROM ncic_weapons WHERE serial_number='${SERIAL}' LIMIT 1")

WEAPON_FOUND="false"
WEAPON_ID=""
NAME_ID=""
CURRENT_COLOR=""
WEAPON_NAME=""
OWNER_NAME=""

if [ -n "$WEAPON_DATA" ]; then
    WEAPON_FOUND="true"
    WEAPON_ID=$(echo "$WEAPON_DATA" | cut -f1)
    NAME_ID=$(echo "$WEAPON_DATA" | cut -f2)
    CURRENT_COLOR=$(echo "$WEAPON_DATA" | cut -f3)
    WEAPON_NAME=$(echo "$WEAPON_DATA" | cut -f4)
    
    # Get Owner Name to verify it's still linked to Sarah
    if [ -n "$NAME_ID" ]; then
        OWNER_NAME=$(opencad_db_query "SELECT name FROM ncic_names WHERE id=${NAME_ID}")
    fi
fi

# Get timestamp info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Construct JSON result
RESULT_JSON=$(cat << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "weapon_found": $WEAPON_FOUND,
    "weapon": {
        "id": "$(json_escape "${WEAPON_ID}")",
        "serial": "$(json_escape "${SERIAL}")",
        "color": "$(json_escape "${CURRENT_COLOR}")",
        "model": "$(json_escape "${WEAPON_NAME}")",
        "owner_name": "$(json_escape "${OWNER_NAME}")",
        "name_id": "$(json_escape "${NAME_ID}")"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_result "$RESULT_JSON" /tmp/update_registered_weapon_color_result.json

echo "Result saved to /tmp/update_registered_weapon_color_result.json"
cat /tmp/update_registered_weapon_color_result.json
echo "=== Export complete ==="