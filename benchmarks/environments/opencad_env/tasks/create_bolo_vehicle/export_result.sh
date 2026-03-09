#!/bin/bash
echo "=== Exporting create_bolo_vehicle result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

INITIAL_BOLO_COUNT=$(cat /tmp/initial_bolo_count 2>/dev/null || echo "0")
CURRENT_BOLO_COUNT=$(get_bolo_vehicle_count)

# Read baseline max ID to filter out pre-existing seed data
BASELINE_MAX_BOLO=$(cat /tmp/baseline_max_bolo_id 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_MAX_BOLO=${BASELINE_MAX_BOLO:-0}

# Search for the BOLO - only consider records NEWER than baseline
BOLO_FOUND="false"
BOLO_ID=""
BOLO_MAKE=""
BOLO_MODEL=""
BOLO_PLATE=""
BOLO_COLOR1=""
BOLO_COLOR2=""
BOLO_REASON=""
BOLO_LAST_SEEN=""

# Search by plate (only new records)
BOLO_ID=$(opencad_db_query "SELECT id FROM bolos_vehicles WHERE UPPER(TRIM(vehicle_plate))='XKCD420' AND id > ${BASELINE_MAX_BOLO} ORDER BY id DESC LIMIT 1")

if [ -z "$BOLO_ID" ]; then
    # Partial plate match (only new records)
    BOLO_ID=$(opencad_db_query "SELECT id FROM bolos_vehicles WHERE UPPER(vehicle_plate) LIKE '%XKCD%' AND id > ${BASELINE_MAX_BOLO} ORDER BY id DESC LIMIT 1")
fi

if [ -z "$BOLO_ID" ]; then
    # Search by make/model (only new records)
    BOLO_ID=$(opencad_db_query "SELECT id FROM bolos_vehicles WHERE LOWER(vehicle_make) LIKE '%declasse%' AND LOWER(vehicle_model) LIKE '%vigero%' AND id > ${BASELINE_MAX_BOLO} ORDER BY id DESC LIMIT 1")
fi

if [ -z "$BOLO_ID" ]; then
    # Any new BOLO after baseline
    BOLO_ID=$(opencad_db_query "SELECT id FROM bolos_vehicles WHERE id > ${BASELINE_MAX_BOLO} ORDER BY id DESC LIMIT 1")
fi

if [ -n "$BOLO_ID" ]; then
    BOLO_FOUND="true"
    BOLO_MAKE=$(opencad_db_query "SELECT vehicle_make FROM bolos_vehicles WHERE id=${BOLO_ID}")
    BOLO_MODEL=$(opencad_db_query "SELECT vehicle_model FROM bolos_vehicles WHERE id=${BOLO_ID}")
    BOLO_PLATE=$(opencad_db_query "SELECT vehicle_plate FROM bolos_vehicles WHERE id=${BOLO_ID}")
    BOLO_COLOR1=$(opencad_db_query "SELECT primary_color FROM bolos_vehicles WHERE id=${BOLO_ID}")
    BOLO_COLOR2=$(opencad_db_query "SELECT secondary_color FROM bolos_vehicles WHERE id=${BOLO_ID}")
    BOLO_REASON=$(opencad_db_query "SELECT reason_wanted FROM bolos_vehicles WHERE id=${BOLO_ID}")
    BOLO_LAST_SEEN=$(opencad_db_query "SELECT last_seen FROM bolos_vehicles WHERE id=${BOLO_ID}")
fi

RESULT_JSON=$(cat << EOF
{
    "initial_bolo_count": ${INITIAL_BOLO_COUNT:-0},
    "current_bolo_count": ${CURRENT_BOLO_COUNT:-0},
    "bolo_found": ${BOLO_FOUND},
    "bolo": {
        "id": "$(json_escape "${BOLO_ID}")",
        "make": "$(json_escape "${BOLO_MAKE}")",
        "model": "$(json_escape "${BOLO_MODEL}")",
        "plate": "$(json_escape "${BOLO_PLATE}")",
        "primary_color": "$(json_escape "${BOLO_COLOR1}")",
        "secondary_color": "$(json_escape "${BOLO_COLOR2}")",
        "reason": "$(json_escape "${BOLO_REASON}")",
        "last_seen": "$(json_escape "${BOLO_LAST_SEEN}")"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_result "$RESULT_JSON" /tmp/create_bolo_vehicle_result.json

echo "Result saved to /tmp/create_bolo_vehicle_result.json"
cat /tmp/create_bolo_vehicle_result.json
echo "=== Export complete ==="
