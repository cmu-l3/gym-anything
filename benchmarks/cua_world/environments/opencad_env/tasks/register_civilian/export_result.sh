#!/bin/bash
echo "=== Exporting register_civilian result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

INITIAL_CIV_COUNT=$(cat /tmp/initial_civilian_count 2>/dev/null || echo "0")
CURRENT_CIV_COUNT=$(get_civilian_count)

# Read baseline max ID to filter out pre-existing seed data
BASELINE_MAX_NCIC=$(cat /tmp/baseline_max_ncic_id 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_MAX_NCIC=${BASELINE_MAX_NCIC:-0}

# In OpenCAD, registering a civilian creates a record in ncic_names
# and a link in civilian_names (junction: user_id, names_id).
# The ncic_names table has a single 'name' field (not first/last).
CIV_FOUND="false"
CIV_ID=""
CIV_NAME=""
CIV_DOB=""
CIV_GENDER=""
CIV_ADDRESS=""
CIV_DL_STATUS=""

# Search ncic_names for Wade Hebert (only new records)
CIV_ID=$(opencad_db_query "SELECT id FROM ncic_names WHERE LOWER(name) LIKE '%wade%hebert%' AND id > ${BASELINE_MAX_NCIC} ORDER BY id DESC LIMIT 1")

if [ -z "$CIV_ID" ]; then
    # Partial match (only new records)
    CIV_ID=$(opencad_db_query "SELECT id FROM ncic_names WHERE LOWER(name) LIKE '%wade%' AND id > ${BASELINE_MAX_NCIC} ORDER BY id DESC LIMIT 1")
fi

if [ -z "$CIV_ID" ]; then
    # Any new ncic_names record after baseline
    CIV_ID=$(opencad_db_query "SELECT id FROM ncic_names WHERE id > ${BASELINE_MAX_NCIC} ORDER BY id DESC LIMIT 1")
fi

if [ -n "$CIV_ID" ]; then
    CIV_FOUND="true"
    CIV_NAME=$(opencad_db_query "SELECT name FROM ncic_names WHERE id=${CIV_ID}")
    CIV_DOB=$(opencad_db_query "SELECT dob FROM ncic_names WHERE id=${CIV_ID}")
    CIV_GENDER=$(opencad_db_query "SELECT gender FROM ncic_names WHERE id=${CIV_ID}")
    CIV_ADDRESS=$(opencad_db_query "SELECT address FROM ncic_names WHERE id=${CIV_ID}")
    CIV_DL_STATUS=$(opencad_db_query "SELECT dl_status FROM ncic_names WHERE id=${CIV_ID}")
fi

RESULT_JSON=$(cat << EOF
{
    "initial_civilian_count": ${INITIAL_CIV_COUNT:-0},
    "current_civilian_count": ${CURRENT_CIV_COUNT:-0},
    "civilian_found": ${CIV_FOUND},
    "civilian": {
        "id": "$(json_escape "${CIV_ID}")",
        "name": "$(json_escape "${CIV_NAME}")",
        "dob": "$(json_escape "${CIV_DOB}")",
        "gender": "$(json_escape "${CIV_GENDER}")",
        "address": "$(json_escape "${CIV_ADDRESS}")",
        "dl_status": "$(json_escape "${CIV_DL_STATUS}")"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_result "$RESULT_JSON" /tmp/register_civilian_result.json

echo "Result saved to /tmp/register_civilian_result.json"
cat /tmp/register_civilian_result.json
echo "=== Export complete ==="
