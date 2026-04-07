#!/bin/bash
echo "=== Exporting add_street result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get initial data
INITIAL_STREET_COUNT=$(cat /tmp/initial_street_count 2>/dev/null || echo "0")
BASELINE_MAX_ID=$(cat /tmp/baseline_max_street_id 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_MAX_ID=${BASELINE_MAX_ID:-0}

# Get current state
CURRENT_STREET_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM streets")

# Search for the street - strictly check for records created AFTER the setup (id > baseline)
# This prevents pre-existing data from counting
STREET_FOUND="false"
STREET_ID=""
STREET_NAME=""

# Exact match check first
STREET_ID=$(opencad_db_query "SELECT id FROM streets WHERE LOWER(TRIM(name)) = 'quarry ridge haul rd' AND id > ${BASELINE_MAX_ID} LIMIT 1")

if [ -z "$STREET_ID" ]; then
    # Partial match check
    STREET_ID=$(opencad_db_query "SELECT id FROM streets WHERE LOWER(name) LIKE '%quarry ridge haul rd%' AND id > ${BASELINE_MAX_ID} LIMIT 1")
fi

if [ -n "$STREET_ID" ]; then
    STREET_FOUND="true"
    STREET_NAME=$(opencad_db_query "SELECT name FROM streets WHERE id=${STREET_ID}")
fi

# Check if app was accessible (basic sanity check)
APP_ACCESSIBLE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/index.php || echo "000")

RESULT_JSON=$(cat << EOF
{
    "initial_count": ${INITIAL_STREET_COUNT:-0},
    "current_count": ${CURRENT_STREET_COUNT:-0},
    "baseline_max_id": ${BASELINE_MAX_ID},
    "street_found": ${STREET_FOUND},
    "street": {
        "id": "$(json_escape "${STREET_ID}")",
        "name": "$(json_escape "${STREET_NAME}")"
    },
    "app_accessible": "${APP_ACCESSIBLE}",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_result "$RESULT_JSON" /tmp/add_street_result.json

echo "Result saved to /tmp/add_street_result.json"
cat /tmp/add_street_result.json
echo "=== Export complete ==="