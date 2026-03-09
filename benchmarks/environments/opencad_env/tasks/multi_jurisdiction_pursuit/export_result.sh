#!/bin/bash
echo "=== Exporting multi_jurisdiction_pursuit result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

BASELINE_ACTIVE=$(cat /tmp/mjp_baseline_active_call 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_HISTORY=$(cat /tmp/mjp_baseline_history_call 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_BOLO_VEH=$(cat /tmp/mjp_baseline_bolo_vehicle 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_WARRANT=$(cat /tmp/mjp_baseline_warrant 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_CITATION=$(cat /tmp/mjp_baseline_citation 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_ACTIVE=${BASELINE_ACTIVE:-0}
BASELINE_HISTORY=${BASELINE_HISTORY:-0}
BASELINE_BOLO_VEH=${BASELINE_BOLO_VEH:-0}
BASELINE_WARRANT=${BASELINE_WARRANT:-0}
BASELINE_CITATION=${BASELINE_CITATION:-0}

# --- CALL (search for 10-80 pursuit) ---
CALL_ID=""
CALL_FOUND="false"
CALL_TYPE=""
CALL_PRIMARY=""
CALL_STREET1=""
CALL_STREET2=""
CALL_NARRATIVE=""

CALL_ID=$(opencad_db_query "SELECT call_id FROM calls WHERE call_type LIKE '%10-80%' AND call_id > ${BASELINE_ACTIVE} ORDER BY call_id DESC LIMIT 1")
if [ -z "$CALL_ID" ]; then
    CALL_ID=$(opencad_db_query "SELECT call_id FROM call_history WHERE call_type LIKE '%10-80%' AND call_id > ${BASELINE_HISTORY} ORDER BY call_id DESC LIMIT 1")
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

# --- VEHICLE BOLO (search by plate BLC-4491) ---
VEH_BOLO_ID=""
VEH_BOLO_FOUND="false"
VEH_BOLO_MAKE=""
VEH_BOLO_MODEL=""
VEH_BOLO_PLATE=""
VEH_BOLO_COLOR=""
VEH_BOLO_REASON=""

VEH_BOLO_ID=$(opencad_db_query "SELECT id FROM bolos_vehicles WHERE UPPER(REPLACE(vehicle_plate,'-','')) LIKE '%BLC4491%' AND id > ${BASELINE_BOLO_VEH} ORDER BY id DESC LIMIT 1")
if [ -z "$VEH_BOLO_ID" ]; then
    VEH_BOLO_ID=$(opencad_db_query "SELECT id FROM bolos_vehicles WHERE UPPER(vehicle_plate) LIKE '%BLC%' AND id > ${BASELINE_BOLO_VEH} ORDER BY id DESC LIMIT 1")
fi
if [ -z "$VEH_BOLO_ID" ]; then
    VEH_BOLO_ID=$(opencad_db_query "SELECT id FROM bolos_vehicles WHERE id > ${BASELINE_BOLO_VEH} ORDER BY id DESC LIMIT 1")
fi

if [ -n "$VEH_BOLO_ID" ]; then
    VEH_BOLO_FOUND="true"
    VEH_BOLO_MAKE=$(opencad_db_query "SELECT COALESCE(vehicle_make,'') FROM bolos_vehicles WHERE id=${VEH_BOLO_ID}")
    VEH_BOLO_MODEL=$(opencad_db_query "SELECT COALESCE(vehicle_model,'') FROM bolos_vehicles WHERE id=${VEH_BOLO_ID}")
    VEH_BOLO_PLATE=$(opencad_db_query "SELECT COALESCE(vehicle_plate,'') FROM bolos_vehicles WHERE id=${VEH_BOLO_ID}")
    VEH_BOLO_COLOR=$(opencad_db_query "SELECT COALESCE(primary_color,'') FROM bolos_vehicles WHERE id=${VEH_BOLO_ID}")
    VEH_BOLO_REASON=$(opencad_db_query "SELECT COALESCE(reason_wanted,'') FROM bolos_vehicles WHERE id=${VEH_BOLO_ID}")
fi

# --- WARRANT (check for Trevor Philips name_id=3, flag wrong-target) ---
WARRANT_ID=""
WARRANT_FOUND="false"
WARRANT_NAME_ID=""
WARRANT_NAME=""
WARRANT_AGENCY=""
TREVOR_WARRANT_FOUND="false"

# Prefer Trevor's new warrant; fall back to any new warrant
WARRANT_ID=$(opencad_db_query "SELECT id FROM ncic_warrants WHERE name_id=3 AND id > ${BASELINE_WARRANT} ORDER BY id DESC LIMIT 1")
if [ -z "$WARRANT_ID" ]; then
    WARRANT_ID=$(opencad_db_query "SELECT id FROM ncic_warrants WHERE id > ${BASELINE_WARRANT} ORDER BY id DESC LIMIT 1")
fi

if [ -n "$WARRANT_ID" ]; then
    WARRANT_FOUND="true"
    WARRANT_NAME_ID=$(opencad_db_query "SELECT COALESCE(name_id,'') FROM ncic_warrants WHERE id=${WARRANT_ID}")
    WARRANT_NAME=$(opencad_db_query "SELECT COALESCE(warrant_name,'') FROM ncic_warrants WHERE id=${WARRANT_ID}")
    WARRANT_AGENCY=$(opencad_db_query "SELECT COALESCE(issuing_agency,'') FROM ncic_warrants WHERE id=${WARRANT_ID}")
    if [ "${WARRANT_NAME_ID}" = "3" ]; then
        TREVOR_WARRANT_FOUND="true"
    fi
fi

# --- CITATION (check for Trevor Philips name_id=3, flag wrong-target) ---
CITATION_ID=""
CITATION_FOUND="false"
CITATION_NAME_ID=""
CITATION_NAME=""
CITATION_FINE=""
TREVOR_CITATION_FOUND="false"

# Prefer Trevor's new citation; fall back to any new citation
CITATION_ID=$(opencad_db_query "SELECT id FROM ncic_citations WHERE name_id=3 AND id > ${BASELINE_CITATION} ORDER BY id DESC LIMIT 1")
if [ -z "$CITATION_ID" ]; then
    CITATION_ID=$(opencad_db_query "SELECT id FROM ncic_citations WHERE id > ${BASELINE_CITATION} ORDER BY id DESC LIMIT 1")
fi

if [ -n "$CITATION_ID" ]; then
    CITATION_FOUND="true"
    CITATION_NAME_ID=$(opencad_db_query "SELECT COALESCE(name_id,'') FROM ncic_citations WHERE id=${CITATION_ID}")
    CITATION_NAME=$(opencad_db_query "SELECT COALESCE(citation_name,'') FROM ncic_citations WHERE id=${CITATION_ID}")
    CITATION_FINE=$(opencad_db_query "SELECT COALESCE(citation_fine,'0') FROM ncic_citations WHERE id=${CITATION_ID}")
    if [ "${CITATION_NAME_ID}" = "3" ]; then
        TREVOR_CITATION_FOUND="true"
    fi
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
    "vehicle_bolo_found": ${VEH_BOLO_FOUND},
    "vehicle_bolo": {
        "id": "$(json_escape "${VEH_BOLO_ID}")",
        "make": "$(json_escape "${VEH_BOLO_MAKE}")",
        "model": "$(json_escape "${VEH_BOLO_MODEL}")",
        "plate": "$(json_escape "${VEH_BOLO_PLATE}")",
        "primary_color": "$(json_escape "${VEH_BOLO_COLOR}")",
        "reason": "$(json_escape "${VEH_BOLO_REASON}")"
    },
    "warrant_found": ${WARRANT_FOUND},
    "trevor_warrant_found": ${TREVOR_WARRANT_FOUND},
    "warrant": {
        "id": "$(json_escape "${WARRANT_ID}")",
        "name_id": "$(json_escape "${WARRANT_NAME_ID}")",
        "warrant_name": "$(json_escape "${WARRANT_NAME}")",
        "issuing_agency": "$(json_escape "${WARRANT_AGENCY}")"
    },
    "citation_found": ${CITATION_FOUND},
    "trevor_citation_found": ${TREVOR_CITATION_FOUND},
    "citation": {
        "id": "$(json_escape "${CITATION_ID}")",
        "name_id": "$(json_escape "${CITATION_NAME_ID}")",
        "citation_name": "$(json_escape "${CITATION_NAME}")",
        "fine": "$(json_escape "${CITATION_FINE}")"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_result "$RESULT_JSON" /tmp/multi_jurisdiction_pursuit_result.json

echo "Result saved to /tmp/multi_jurisdiction_pursuit_result.json"
cat /tmp/multi_jurisdiction_pursuit_result.json
echo "=== Export complete ==="
