#!/bin/bash
echo "=== Exporting dispatch_new_incident_type result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

# Read baselines
INITIAL_TYPE_COUNT=$(cat /tmp/initial_type_count 2>/dev/null || echo "0")
INITIAL_CALL_COUNT=$(cat /tmp/initial_call_count 2>/dev/null || echo "0")
BASELINE_MAX_TYPE=$(cat /tmp/baseline_max_type_id 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_MAX_CALL=$(cat /tmp/baseline_max_call_id 2>/dev/null | tr -cd '0-9' || echo "0")

BASELINE_MAX_TYPE=${BASELINE_MAX_TYPE:-0}
BASELINE_MAX_CALL=${BASELINE_MAX_CALL:-0}

# 1. Check for the new Incident Type "Rock Slide"
TYPE_FOUND="false"
TYPE_ID=""
TYPE_NAME=""

# Search strictly for Rock Slide (case insensitive) created after baseline
# Note: incident_types table usually has columns: id, incident_type (or name), etc.
# We check schema assumption or just query common columns. Standard OpenCAD uses 'incident_type'.
TYPE_ID=$(opencad_db_query "SELECT id FROM incident_types WHERE LOWER(incident_type) LIKE '%rock%slide%' AND id > ${BASELINE_MAX_TYPE} ORDER BY id DESC LIMIT 1")

if [ -n "$TYPE_ID" ]; then
    TYPE_FOUND="true"
    TYPE_NAME=$(opencad_db_query "SELECT incident_type FROM incident_types WHERE id=${TYPE_ID}")
else
    # Fallback check if it existed before (though task says it shouldn't)
    TYPE_ID=$(opencad_db_query "SELECT id FROM incident_types WHERE LOWER(incident_type) LIKE '%rock%slide%' LIMIT 1")
    if [ -n "$TYPE_ID" ]; then
        TYPE_FOUND="true"
        TYPE_NAME=$(opencad_db_query "SELECT incident_type FROM incident_types WHERE id=${TYPE_ID}")
        # Mark as pre-existing if ID <= baseline (though verifier logic handles this via timestamp/counts)
    fi
fi

# 2. Check for the Call at "North Haul Road"
CALL_FOUND="false"
CALL_ID=""
CALL_LOCATION=""
CALL_TYPE_VAL=""
LINKED_CORRECTLY="false"

# Search for call by location created after baseline
CALL_ID=$(opencad_db_query "SELECT call_id FROM calls WHERE LOWER(call_location) LIKE '%north%haul%' AND call_id > ${BASELINE_MAX_CALL} ORDER BY call_id DESC LIMIT 1")

if [ -n "$CALL_ID" ]; then
    CALL_FOUND="true"
    CALL_LOCATION=$(opencad_db_query "SELECT call_location FROM calls WHERE call_id=${CALL_ID}")
    CALL_TYPE_VAL=$(opencad_db_query "SELECT call_type FROM calls WHERE call_id=${CALL_ID}")
    
    # Check linkage
    # In OpenCAD, call_type often stores the string name, but sometimes the ID. We check both against our found type.
    if [ -n "$TYPE_NAME" ] && [[ "$CALL_TYPE_VAL" == "$TYPE_NAME" ]]; then
        LINKED_CORRECTLY="true"
    elif [ -n "$TYPE_ID" ] && [[ "$CALL_TYPE_VAL" == "$TYPE_ID" ]]; then
        LINKED_CORRECTLY="true"
    fi
fi

# Current counts for delta verification
CURRENT_TYPE_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM incident_types")
CURRENT_CALL_COUNT=$(get_call_count)

RESULT_JSON=$(cat << EOF
{
    "initial_type_count": ${INITIAL_TYPE_COUNT:-0},
    "current_type_count": ${CURRENT_TYPE_COUNT:-0},
    "initial_call_count": ${INITIAL_CALL_COUNT:-0},
    "current_call_count": ${CURRENT_CALL_COUNT:-0},
    "type_found": ${TYPE_FOUND},
    "created_type": {
        "id": "$(json_escape "${TYPE_ID}")",
        "name": "$(json_escape "${TYPE_NAME}")"
    },
    "call_found": ${CALL_FOUND},
    "created_call": {
        "id": "$(json_escape "${CALL_ID}")",
        "location": "$(json_escape "${CALL_LOCATION}")",
        "type_value": "$(json_escape "${CALL_TYPE_VAL}")"
    },
    "linked_correctly": ${LINKED_CORRECTLY},
    "timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_result "$RESULT_JSON" /tmp/dispatch_new_incident_type_result.json

echo "Result saved to /tmp/dispatch_new_incident_type_result.json"
cat /tmp/dispatch_new_incident_type_result.json
echo "=== Export complete ==="