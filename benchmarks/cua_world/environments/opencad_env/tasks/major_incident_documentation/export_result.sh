#!/bin/bash
echo "=== Exporting major_incident_documentation result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

BASELINE_ACTIVE=$(cat /tmp/mid_baseline_active_call 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_HISTORY=$(cat /tmp/mid_baseline_history_call 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_CITATION=$(cat /tmp/mid_baseline_citation 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_BOLO_PERSON=$(cat /tmp/mid_baseline_bolo_person 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_ACTIVE=${BASELINE_ACTIVE:-0}
BASELINE_HISTORY=${BASELINE_HISTORY:-0}
BASELINE_CITATION=${BASELINE_CITATION:-0}
BASELINE_BOLO_PERSON=${BASELINE_BOLO_PERSON:-0}

# --- CALL (search for 10-70 structure fire) ---
CALL_ID=""
CALL_FOUND="false"
CALL_TYPE=""
CALL_PRIMARY=""
CALL_STREET1=""
CALL_STREET2=""
CALL_NARRATIVE=""

CALL_ID=$(opencad_db_query "SELECT call_id FROM calls WHERE call_type LIKE '%10-70%' AND call_id > ${BASELINE_ACTIVE} ORDER BY call_id DESC LIMIT 1")
if [ -z "$CALL_ID" ]; then
    CALL_ID=$(opencad_db_query "SELECT call_id FROM call_history WHERE call_type LIKE '%10-70%' AND call_id > ${BASELINE_HISTORY} ORDER BY call_id DESC LIMIT 1")
fi
if [ -z "$CALL_ID" ]; then
    CALL_ID=$(opencad_db_query "SELECT call_id FROM calls WHERE call_id > ${BASELINE_ACTIVE} ORDER BY call_id DESC LIMIT 1")
fi
if [ -z "$CALL_ID" ]; then
    CALL_ID=$(opencad_db_query "SELECT call_id FROM call_history WHERE call_id > ${BASELINE_HISTORY} ORDER BY call_id DESC LIMIT 1")
fi

if [ -n "$CALL_ID" ]; then
    CALL_FOUND="true"
    CALL_TYPE=$(opencad_db_query "SELECT COALESCE(call_type,'') FROM calls WHERE call_id=${CALL_ID}" 2>/dev/null)
    if [ -z "$CALL_TYPE" ]; then
        CALL_TYPE=$(opencad_db_query "SELECT COALESCE(call_type,'') FROM call_history WHERE call_id=${CALL_ID}")
        CALL_PRIMARY=$(opencad_db_query "SELECT COALESCE(call_primary,'') FROM call_history WHERE call_id=${CALL_ID}")
        CALL_STREET1=$(opencad_db_query "SELECT COALESCE(call_street1,'') FROM call_history WHERE call_id=${CALL_ID}")
        CALL_STREET2=$(opencad_db_query "SELECT COALESCE(call_street2,'') FROM call_history WHERE call_id=${CALL_ID}")
        CALL_NARRATIVE=$(opencad_db_query "SELECT COALESCE(call_narrative,'') FROM call_history WHERE call_id=${CALL_ID}")
    else
        CALL_PRIMARY=$(opencad_db_query "SELECT COALESCE(call_primary,'') FROM calls WHERE call_id=${CALL_ID}")
        CALL_STREET1=$(opencad_db_query "SELECT COALESCE(call_street1,'') FROM calls WHERE call_id=${CALL_ID}")
        CALL_STREET2=$(opencad_db_query "SELECT COALESCE(call_street2,'') FROM calls WHERE call_id=${CALL_ID}")
        CALL_NARRATIVE=$(opencad_db_query "SELECT COALESCE(call_narrative,'') FROM calls WHERE call_id=${CALL_ID}")
    fi
fi

# --- CITATION (check for any new citation, flag if for Michael De Santa name_id=1) ---
CITATION_ID=""
CITATION_NAME_ID=""
CITATION_NAME=""
CITATION_FINE=""
CITATION_FOUND="false"
MICHAEL_CITATION_FOUND="false"

CITATION_ID=$(opencad_db_query "SELECT id FROM ncic_citations WHERE id > ${BASELINE_CITATION} ORDER BY id DESC LIMIT 1")
if [ -n "$CITATION_ID" ]; then
    CITATION_FOUND="true"
    CITATION_NAME_ID=$(opencad_db_query "SELECT COALESCE(name_id,'') FROM ncic_citations WHERE id=${CITATION_ID}")
    CITATION_NAME=$(opencad_db_query "SELECT COALESCE(citation_name,'') FROM ncic_citations WHERE id=${CITATION_ID}")
    CITATION_FINE=$(opencad_db_query "SELECT COALESCE(citation_fine,'0') FROM ncic_citations WHERE id=${CITATION_ID}")
    if [ "${CITATION_NAME_ID}" = "1" ]; then
        MICHAEL_CITATION_FOUND="true"
    fi
fi

# --- PERSON BOLO ---
BOLO_ID=""
BOLO_FIRST=""
BOLO_LAST=""
BOLO_GENDER=""
BOLO_DESC=""
BOLO_REASON=""
BOLO_FOUND="false"

BOLO_ID=$(opencad_db_query "SELECT id FROM bolos_persons WHERE id > ${BASELINE_BOLO_PERSON} ORDER BY id DESC LIMIT 1")
if [ -n "$BOLO_ID" ]; then
    BOLO_FOUND="true"
    BOLO_FIRST=$(opencad_db_query "SELECT COALESCE(first_name,'') FROM bolos_persons WHERE id=${BOLO_ID}")
    BOLO_LAST=$(opencad_db_query "SELECT COALESCE(last_name,'') FROM bolos_persons WHERE id=${BOLO_ID}")
    BOLO_GENDER=$(opencad_db_query "SELECT COALESCE(gender,'') FROM bolos_persons WHERE id=${BOLO_ID}")
    BOLO_DESC=$(opencad_db_query "SELECT COALESCE(physical_description,'') FROM bolos_persons WHERE id=${BOLO_ID}")
    BOLO_REASON=$(opencad_db_query "SELECT COALESCE(reason_wanted,'') FROM bolos_persons WHERE id=${BOLO_ID}")
fi

RESULT_JSON=$(cat << EOF
{
    "call_found": ${CALL_FOUND},
    "call": {
        "id": "$(json_escape "${CALL_ID}")",
        "type": "$(json_escape "${CALL_TYPE}")",
        "primary": "$(json_escape "${CALL_PRIMARY}")",
        "street1": "$(json_escape "${CALL_STREET1}")",
        "street2": "$(json_escape "${CALL_STREET2}")",
        "narrative": "$(json_escape "${CALL_NARRATIVE}")"
    },
    "citation_found": ${CITATION_FOUND},
    "michael_citation_found": ${MICHAEL_CITATION_FOUND},
    "citation": {
        "id": "$(json_escape "${CITATION_ID}")",
        "name_id": "$(json_escape "${CITATION_NAME_ID}")",
        "citation_name": "$(json_escape "${CITATION_NAME}")",
        "fine": "$(json_escape "${CITATION_FINE}")"
    },
    "bolo_person_found": ${BOLO_FOUND},
    "bolo_person": {
        "id": "$(json_escape "${BOLO_ID}")",
        "first_name": "$(json_escape "${BOLO_FIRST}")",
        "last_name": "$(json_escape "${BOLO_LAST}")",
        "gender": "$(json_escape "${BOLO_GENDER}")",
        "physical_description": "$(json_escape "${BOLO_DESC}")",
        "reason_wanted": "$(json_escape "${BOLO_REASON}")"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_result "$RESULT_JSON" /tmp/major_incident_documentation_result.json

echo "Result saved to /tmp/major_incident_documentation_result.json"
cat /tmp/major_incident_documentation_result.json
echo "=== Export complete ==="
