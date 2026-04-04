#!/bin/bash
echo "=== Exporting create_dispatch_call result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

INITIAL_CALL_COUNT=$(cat /tmp/initial_call_count 2>/dev/null || echo "0")
CURRENT_CALL_COUNT=$(get_call_count)

# Read baseline max IDs to filter out pre-existing seed data
BASELINE_MAX_ACTIVE=$(cat /tmp/baseline_max_active_call_id 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_MAX_HISTORY=$(cat /tmp/baseline_max_history_call_id 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_MAX_ACTIVE=${BASELINE_MAX_ACTIVE:-0}
BASELINE_MAX_HISTORY=${BASELINE_MAX_HISTORY:-0}

# Search for the dispatch call - only consider records NEWER than baseline
CALL_ID=""
CALL_TYPE=""
CALL_PRIMARY=""
CALL_STREET1=""
CALL_STREET2=""
CALL_NARRATIVE=""
CALL_FOUND="false"

# Search in active calls (only new records)
CALL_ID=$(opencad_db_query "SELECT call_id FROM calls WHERE call_type LIKE '%10-50%' AND call_id > ${BASELINE_MAX_ACTIVE} ORDER BY call_id DESC LIMIT 1")

if [ -z "$CALL_ID" ]; then
    # Try broader search - any new call after baseline
    CALL_ID=$(opencad_db_query "SELECT call_id FROM calls WHERE call_id > ${BASELINE_MAX_ACTIVE} ORDER BY call_id DESC LIMIT 1")
fi

if [ -z "$CALL_ID" ]; then
    # Search in call history too (calls move here when closed) - only new records
    CALL_ID=$(opencad_db_query "SELECT call_id FROM call_history WHERE call_type LIKE '%10-50%' AND call_id > ${BASELINE_MAX_HISTORY} ORDER BY call_id DESC LIMIT 1")
fi

if [ -n "$CALL_ID" ]; then
    CALL_FOUND="true"
    # Try active calls table first
    CALL_TYPE=$(opencad_db_query "SELECT call_type FROM calls WHERE call_id=${CALL_ID}" 2>/dev/null)
    if [ -n "$CALL_TYPE" ]; then
        CALL_PRIMARY=$(opencad_db_query "SELECT call_primary FROM calls WHERE call_id=${CALL_ID}")
        CALL_STREET1=$(opencad_db_query "SELECT call_street1 FROM calls WHERE call_id=${CALL_ID}")
        CALL_STREET2=$(opencad_db_query "SELECT call_street2 FROM calls WHERE call_id=${CALL_ID}")
        CALL_NARRATIVE=$(opencad_db_query "SELECT call_narrative FROM calls WHERE call_id=${CALL_ID}")
    else
        # Try call history
        CALL_TYPE=$(opencad_db_query "SELECT call_type FROM call_history WHERE call_id=${CALL_ID}")
        CALL_PRIMARY=$(opencad_db_query "SELECT call_primary FROM call_history WHERE call_id=${CALL_ID}")
        CALL_STREET1=$(opencad_db_query "SELECT call_street1 FROM call_history WHERE call_id=${CALL_ID}")
        CALL_STREET2=$(opencad_db_query "SELECT call_street2 FROM call_history WHERE call_id=${CALL_ID}")
        CALL_NARRATIVE=$(opencad_db_query "SELECT call_narrative FROM call_history WHERE call_id=${CALL_ID}")
    fi
fi

# Build result JSON
RESULT_JSON=$(cat << EOF
{
    "initial_call_count": ${INITIAL_CALL_COUNT:-0},
    "current_call_count": ${CURRENT_CALL_COUNT:-0},
    "call_found": ${CALL_FOUND},
    "call": {
        "id": "$(json_escape "${CALL_ID}")",
        "type": "$(json_escape "${CALL_TYPE}")",
        "primary": "$(json_escape "${CALL_PRIMARY}")",
        "street1": "$(json_escape "${CALL_STREET1}")",
        "street2": "$(json_escape "${CALL_STREET2}")",
        "narrative": "$(json_escape "${CALL_NARRATIVE}")"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_result "$RESULT_JSON" /tmp/create_dispatch_call_result.json

echo "Result saved to /tmp/create_dispatch_call_result.json"
cat /tmp/create_dispatch_call_result.json
echo "=== Export complete ==="
