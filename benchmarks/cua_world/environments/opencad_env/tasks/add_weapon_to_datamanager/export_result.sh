#!/bin/bash
echo "=== Exporting add_weapon_to_datamanager result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Retrieve setup data
INITIAL_COUNT=$(cat /tmp/initial_weapon_count 2>/dev/null || echo "0")
BASELINE_MAX_ID=$(cat /tmp/baseline_max_weapon_id 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_MAX_ID=${BASELINE_MAX_ID:-0}

# Get current state
CURRENT_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM weapons" 2>/dev/null || echo "0")

# Search for the specific weapon added
# We look for records with ID > BASELINE_MAX_ID to ensure it was added during this session
# We check common column names for weapons table (usually 'name' or 'weapon_name')
WEAPON_FOUND="false"
WEAPON_ID=""
WEAPON_NAME=""
WEAPON_TYPE=""

# Query attempt 1: Standard schema
# Note: Using LIKE for case-insensitive partial match robustness, but verifying specifics later
WEAPON_ID=$(opencad_db_query "SELECT weapon_id FROM weapons WHERE (LOWER(name) LIKE '%remington%' OR LOWER(name) LIKE '%breacher%') AND weapon_id > ${BASELINE_MAX_ID} ORDER BY weapon_id DESC LIMIT 1" 2>/dev/null)

# Fallback if column is 'id' instead of 'weapon_id'
if [ -z "$WEAPON_ID" ]; then
    WEAPON_ID=$(opencad_db_query "SELECT id FROM weapons WHERE (LOWER(name) LIKE '%remington%' OR LOWER(name) LIKE '%breacher%') AND id > ${BASELINE_MAX_ID} ORDER BY id DESC LIMIT 1" 2>/dev/null)
fi

if [ -n "$WEAPON_ID" ]; then
    WEAPON_FOUND="true"
    # Fetch details (trying both 'weapon_id' and 'id' column naming conventions if needed)
    # Usually OpenCAD uses 'name' and 'type' columns for this table
    WEAPON_NAME=$(opencad_db_query "SELECT name FROM weapons WHERE weapon_id=${WEAPON_ID} OR id=${WEAPON_ID} LIMIT 1" 2>/dev/null)
    WEAPON_TYPE=$(opencad_db_query "SELECT type FROM weapons WHERE weapon_id=${WEAPON_ID} OR id=${WEAPON_ID} LIMIT 1" 2>/dev/null)
fi

# Prepare JSON result
RESULT_JSON=$(cat << EOF
{
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "weapon_found": ${WEAPON_FOUND},
    "weapon": {
        "id": "$(json_escape "${WEAPON_ID}")",
        "name": "$(json_escape "${WEAPON_NAME}")",
        "type": "$(json_escape "${WEAPON_TYPE}")"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF
)

# Save result with permission handling
safe_write_result "$RESULT_JSON" /tmp/add_weapon_result.json

echo "Result saved to /tmp/add_weapon_result.json"
cat /tmp/add_weapon_result.json
echo "=== Export complete ==="