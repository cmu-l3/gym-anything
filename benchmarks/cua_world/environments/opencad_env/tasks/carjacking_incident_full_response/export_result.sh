#!/bin/bash
echo "=== Exporting carjacking_incident_full_response result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

# --- READ BASELINES ---
BASELINE_NCIC_NAME=$(cat /tmp/cifr_baseline_ncic_name 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_NCIC_PLATE=$(cat /tmp/cifr_baseline_ncic_plate 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_ACTIVE=$(cat /tmp/cifr_baseline_active_call 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_HISTORY=$(cat /tmp/cifr_baseline_history_call 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_BOLO_VEH=$(cat /tmp/cifr_baseline_bolo_vehicle 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_BOLO_PER=$(cat /tmp/cifr_baseline_bolo_person 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_CITATION=$(cat /tmp/cifr_baseline_citation 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_NCIC_NAME=${BASELINE_NCIC_NAME:-0}
BASELINE_NCIC_PLATE=${BASELINE_NCIC_PLATE:-0}
BASELINE_ACTIVE=${BASELINE_ACTIVE:-0}
BASELINE_HISTORY=${BASELINE_HISTORY:-0}
BASELINE_BOLO_VEH=${BASELINE_BOLO_VEH:-0}
BASELINE_BOLO_PER=${BASELINE_BOLO_PER:-0}
BASELINE_CITATION=${BASELINE_CITATION:-0}

# ============================================================
# SECTION 1: CIVILIAN IDENTITY (ncic_names)
# ============================================================
CIV_ID=""
CIV_FOUND="false"
CIV_NAME=""
CIV_DOB=""
CIV_GENDER=""
CIV_ADDRESS=""
CIV_DL=""

# Tiered search: exact name -> partial first -> partial last -> any new record
CIV_ID=$(opencad_db_query "SELECT id FROM ncic_names WHERE LOWER(name) LIKE '%diego%ramirez%' AND id > ${BASELINE_NCIC_NAME} ORDER BY id DESC LIMIT 1")
if [ -z "$CIV_ID" ]; then
    CIV_ID=$(opencad_db_query "SELECT id FROM ncic_names WHERE LOWER(name) LIKE '%diego%' AND id > ${BASELINE_NCIC_NAME} ORDER BY id DESC LIMIT 1")
fi
if [ -z "$CIV_ID" ]; then
    CIV_ID=$(opencad_db_query "SELECT id FROM ncic_names WHERE LOWER(name) LIKE '%ramirez%' AND id > ${BASELINE_NCIC_NAME} ORDER BY id DESC LIMIT 1")
fi
if [ -z "$CIV_ID" ]; then
    CIV_ID=$(opencad_db_query "SELECT id FROM ncic_names WHERE id > ${BASELINE_NCIC_NAME} ORDER BY id DESC LIMIT 1")
fi

if [ -n "$CIV_ID" ]; then
    CIV_FOUND="true"
    CIV_NAME=$(opencad_db_query "SELECT COALESCE(name,'') FROM ncic_names WHERE id=${CIV_ID}")
    CIV_DOB=$(opencad_db_query "SELECT COALESCE(dob,'') FROM ncic_names WHERE id=${CIV_ID}")
    CIV_GENDER=$(opencad_db_query "SELECT COALESCE(gender,'') FROM ncic_names WHERE id=${CIV_ID}")
    CIV_ADDRESS=$(opencad_db_query "SELECT COALESCE(address,'') FROM ncic_names WHERE id=${CIV_ID}")
    CIV_DL=$(opencad_db_query "SELECT COALESCE(dl_status,'') FROM ncic_names WHERE id=${CIV_ID}")
fi

# ============================================================
# SECTION 2: VEHICLE REGISTRATION (ncic_plates)
# ============================================================
PLATE_ID=""
PLATE_FOUND="false"
PLATE_PLATE=""
PLATE_MAKE=""
PLATE_MODEL=""
PLATE_COLOR=""
PLATE_NAME_ID=""
PLATE_LINKED="false"

# Tiered: exact plate -> partial plate -> any new
PLATE_ID=$(opencad_db_query "SELECT id FROM ncic_plates WHERE UPPER(REPLACE(veh_plate,'-','')) LIKE '%DGR2247%' AND id > ${BASELINE_NCIC_PLATE} ORDER BY id DESC LIMIT 1")
if [ -z "$PLATE_ID" ]; then
    PLATE_ID=$(opencad_db_query "SELECT id FROM ncic_plates WHERE UPPER(veh_plate) LIKE '%DGR%' AND id > ${BASELINE_NCIC_PLATE} ORDER BY id DESC LIMIT 1")
fi
if [ -z "$PLATE_ID" ]; then
    PLATE_ID=$(opencad_db_query "SELECT id FROM ncic_plates WHERE id > ${BASELINE_NCIC_PLATE} ORDER BY id DESC LIMIT 1")
fi

if [ -n "$PLATE_ID" ]; then
    PLATE_FOUND="true"
    PLATE_PLATE=$(opencad_db_query "SELECT COALESCE(veh_plate,'') FROM ncic_plates WHERE id=${PLATE_ID}")
    PLATE_MAKE=$(opencad_db_query "SELECT COALESCE(veh_make,'') FROM ncic_plates WHERE id=${PLATE_ID}")
    PLATE_MODEL=$(opencad_db_query "SELECT COALESCE(veh_model,'') FROM ncic_plates WHERE id=${PLATE_ID}")
    PLATE_COLOR=$(opencad_db_query "SELECT COALESCE(veh_pcolor,'') FROM ncic_plates WHERE id=${PLATE_ID}")
    PLATE_NAME_ID=$(opencad_db_query "SELECT COALESCE(name_id,'') FROM ncic_plates WHERE id=${PLATE_ID}")
    if [ -n "$CIV_ID" ] && [ "${PLATE_NAME_ID}" = "${CIV_ID}" ]; then
        PLATE_LINKED="true"
    fi
fi

# ============================================================
# SECTION 3: DISPATCH CALL (calls / call_history)
# ============================================================
CALL_ID=""
CALL_FOUND="false"
CALL_TYPE=""
CALL_STREET1=""
CALL_NARRATIVE=""

# Tiered: 10-64 (Crime in Progress) type -> any new call
CALL_ID=$(opencad_db_query "SELECT call_id FROM calls WHERE call_type LIKE '%10-64%' AND call_id > ${BASELINE_ACTIVE} ORDER BY call_id DESC LIMIT 1")
if [ -z "$CALL_ID" ]; then
    CALL_ID=$(opencad_db_query "SELECT call_id FROM call_history WHERE call_type LIKE '%10-64%' AND call_id > ${BASELINE_HISTORY} ORDER BY call_id DESC LIMIT 1")
fi
if [ -z "$CALL_ID" ]; then
    CALL_ID=$(opencad_db_query "SELECT call_id FROM calls WHERE call_id > ${BASELINE_ACTIVE} ORDER BY call_id DESC LIMIT 1")
fi
if [ -z "$CALL_ID" ]; then
    CALL_ID=$(opencad_db_query "SELECT call_id FROM call_history WHERE call_id > ${BASELINE_HISTORY} ORDER BY call_id DESC LIMIT 1")
fi

if [ -n "$CALL_ID" ]; then
    CALL_FOUND="true"
    # Try active calls first, then history
    CALL_TYPE=$(opencad_db_query "SELECT COALESCE(call_type,'') FROM calls WHERE call_id=${CALL_ID}" 2>/dev/null)
    if [ -z "$CALL_TYPE" ]; then
        CALL_TYPE=$(opencad_db_query "SELECT COALESCE(call_type,'') FROM call_history WHERE call_id=${CALL_ID}")
        CALL_STREET1=$(opencad_db_query "SELECT COALESCE(call_street1,'') FROM call_history WHERE call_id=${CALL_ID}")
        CALL_NARRATIVE=$(opencad_db_query "SELECT COALESCE(call_narrative,'') FROM call_history WHERE call_id=${CALL_ID}")
    else
        CALL_STREET1=$(opencad_db_query "SELECT COALESCE(call_street1,'') FROM calls WHERE call_id=${CALL_ID}")
        CALL_NARRATIVE=$(opencad_db_query "SELECT COALESCE(call_narrative,'') FROM calls WHERE call_id=${CALL_ID}")
    fi
fi

# ============================================================
# SECTION 4: VEHICLE BOLO (bolos_vehicles)
# ============================================================
VEH_BOLO_ID=""
VEH_BOLO_FOUND="false"
VEH_BOLO_MAKE=""
VEH_BOLO_MODEL=""
VEH_BOLO_PLATE=""
VEH_BOLO_COLOR=""
VEH_BOLO_REASON=""

# Tiered: plate match -> partial plate -> any new
VEH_BOLO_ID=$(opencad_db_query "SELECT id FROM bolos_vehicles WHERE UPPER(REPLACE(vehicle_plate,'-','')) LIKE '%DGR2247%' AND id > ${BASELINE_BOLO_VEH} ORDER BY id DESC LIMIT 1")
if [ -z "$VEH_BOLO_ID" ]; then
    VEH_BOLO_ID=$(opencad_db_query "SELECT id FROM bolos_vehicles WHERE UPPER(vehicle_plate) LIKE '%DGR%' AND id > ${BASELINE_BOLO_VEH} ORDER BY id DESC LIMIT 1")
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

# ============================================================
# SECTION 5: CITATION (ncic_citations — prefer Trevor name_id=3)
# ============================================================
CITATION_ID=""
CITATION_FOUND="false"
CITATION_NAME_ID=""
CITATION_NAME=""
CITATION_FINE=""
TREVOR_CITATION_FOUND="false"

# Prefer Trevor's new citation
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

# ============================================================
# SECTION 6: PERSON BOLO (bolos_persons)
# ============================================================
PER_BOLO_ID=""
PER_BOLO_FOUND="false"
PER_BOLO_FNAME=""
PER_BOLO_LNAME=""
PER_BOLO_DESC=""
PER_BOLO_LAST_SEEN=""

# Tiered: name match -> partial -> any new
PER_BOLO_ID=$(opencad_db_query "SELECT id FROM bolos_persons WHERE LOWER(first_name) LIKE '%franklin%' AND LOWER(last_name) LIKE '%clinton%' AND id > ${BASELINE_BOLO_PER} ORDER BY id DESC LIMIT 1")
if [ -z "$PER_BOLO_ID" ]; then
    PER_BOLO_ID=$(opencad_db_query "SELECT id FROM bolos_persons WHERE LOWER(first_name) LIKE '%franklin%' AND id > ${BASELINE_BOLO_PER} ORDER BY id DESC LIMIT 1")
fi
if [ -z "$PER_BOLO_ID" ]; then
    PER_BOLO_ID=$(opencad_db_query "SELECT id FROM bolos_persons WHERE LOWER(last_name) LIKE '%clinton%' AND id > ${BASELINE_BOLO_PER} ORDER BY id DESC LIMIT 1")
fi
if [ -z "$PER_BOLO_ID" ]; then
    PER_BOLO_ID=$(opencad_db_query "SELECT id FROM bolos_persons WHERE id > ${BASELINE_BOLO_PER} ORDER BY id DESC LIMIT 1")
fi

if [ -n "$PER_BOLO_ID" ]; then
    PER_BOLO_FOUND="true"
    PER_BOLO_FNAME=$(opencad_db_query "SELECT COALESCE(first_name,'') FROM bolos_persons WHERE id=${PER_BOLO_ID}")
    PER_BOLO_LNAME=$(opencad_db_query "SELECT COALESCE(last_name,'') FROM bolos_persons WHERE id=${PER_BOLO_ID}")
    PER_BOLO_DESC=$(opencad_db_query "SELECT COALESCE(CONCAT_WS(' ', misc_description, tattoos, build),'') FROM bolos_persons WHERE id=${PER_BOLO_ID}")
    PER_BOLO_LAST_SEEN=$(opencad_db_query "SELECT COALESCE(last_seen,'') FROM bolos_persons WHERE id=${PER_BOLO_ID}")
fi

# ============================================================
# BUILD RESULT JSON
# ============================================================
RESULT_JSON=$(cat << EOF
{
    "civilian_found": ${CIV_FOUND},
    "civilian": {
        "id": "$(json_escape "${CIV_ID}")",
        "name": "$(json_escape "${CIV_NAME}")",
        "dob": "$(json_escape "${CIV_DOB}")",
        "gender": "$(json_escape "${CIV_GENDER}")",
        "address": "$(json_escape "${CIV_ADDRESS}")",
        "dl_status": "$(json_escape "${CIV_DL}")"
    },
    "vehicle_found": ${PLATE_FOUND},
    "vehicle_linked_to_civilian": ${PLATE_LINKED},
    "vehicle": {
        "id": "$(json_escape "${PLATE_ID}")",
        "name_id": "$(json_escape "${PLATE_NAME_ID}")",
        "plate": "$(json_escape "${PLATE_PLATE}")",
        "make": "$(json_escape "${PLATE_MAKE}")",
        "model": "$(json_escape "${PLATE_MODEL}")",
        "color": "$(json_escape "${PLATE_COLOR}")"
    },
    "call_found": ${CALL_FOUND},
    "call": {
        "id": "$(json_escape "${CALL_ID}")",
        "type": "$(json_escape "${CALL_TYPE}")",
        "street1": "$(json_escape "${CALL_STREET1}")",
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
    "citation_found": ${CITATION_FOUND},
    "trevor_citation_found": ${TREVOR_CITATION_FOUND},
    "citation": {
        "id": "$(json_escape "${CITATION_ID}")",
        "name_id": "$(json_escape "${CITATION_NAME_ID}")",
        "citation_name": "$(json_escape "${CITATION_NAME}")",
        "fine": "$(json_escape "${CITATION_FINE}")"
    },
    "person_bolo_found": ${PER_BOLO_FOUND},
    "person_bolo": {
        "id": "$(json_escape "${PER_BOLO_ID}")",
        "first_name": "$(json_escape "${PER_BOLO_FNAME}")",
        "last_name": "$(json_escape "${PER_BOLO_LNAME}")",
        "description": "$(json_escape "${PER_BOLO_DESC}")",
        "last_seen": "$(json_escape "${PER_BOLO_LAST_SEEN}")"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_result "$RESULT_JSON" /tmp/carjacking_incident_full_response_result.json

echo "Result saved to /tmp/carjacking_incident_full_response_result.json"
cat /tmp/carjacking_incident_full_response_result.json
echo "=== Export complete ==="
