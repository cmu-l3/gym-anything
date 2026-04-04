#!/bin/bash
echo "=== Exporting new_resident_full_processing result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

BASELINE_NCIC_NAME=$(cat /tmp/nrfp_baseline_ncic_name 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_NCIC_PLATE=$(cat /tmp/nrfp_baseline_ncic_plate 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_NCIC_WARRANT=$(cat /tmp/nrfp_baseline_ncic_warrant 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_NCIC_NAME=${BASELINE_NCIC_NAME:-0}
BASELINE_NCIC_PLATE=${BASELINE_NCIC_PLATE:-0}
BASELINE_NCIC_WARRANT=${BASELINE_NCIC_WARRANT:-0}

# --- CIVILIAN IDENTITY (ncic_names) ---
CIV_ID=""
CIV_FOUND="false"
CIV_NAME=""
CIV_DOB=""
CIV_GENDER=""
CIV_RACE=""
CIV_DL=""

# Search for new civilian named Lamar Davis; fall back to any new record
CIV_ID=$(opencad_db_query "SELECT id FROM ncic_names WHERE LOWER(name) LIKE '%lamar%' AND id > ${BASELINE_NCIC_NAME} ORDER BY id DESC LIMIT 1")
if [ -z "$CIV_ID" ]; then
    CIV_ID=$(opencad_db_query "SELECT id FROM ncic_names WHERE LOWER(name) LIKE '%davis%' AND id > ${BASELINE_NCIC_NAME} ORDER BY id DESC LIMIT 1")
fi
if [ -z "$CIV_ID" ]; then
    CIV_ID=$(opencad_db_query "SELECT id FROM ncic_names WHERE id > ${BASELINE_NCIC_NAME} ORDER BY id DESC LIMIT 1")
fi

if [ -n "$CIV_ID" ]; then
    CIV_FOUND="true"
    CIV_NAME=$(opencad_db_query "SELECT COALESCE(name,'') FROM ncic_names WHERE id=${CIV_ID}")
    CIV_DOB=$(opencad_db_query "SELECT COALESCE(dob,'') FROM ncic_names WHERE id=${CIV_ID}")
    CIV_GENDER=$(opencad_db_query "SELECT COALESCE(gender,'') FROM ncic_names WHERE id=${CIV_ID}")
    CIV_RACE=$(opencad_db_query "SELECT COALESCE(race,'') FROM ncic_names WHERE id=${CIV_ID}")
    CIV_DL=$(opencad_db_query "SELECT COALESCE(dl_status,'') FROM ncic_names WHERE id=${CIV_ID}")
fi

# --- VEHICLE REGISTRATION (ncic_plates) ---
PLATE_ID=""
PLATE_FOUND="false"
PLATE_PLATE=""
PLATE_MAKE=""
PLATE_MODEL=""
PLATE_COLOR=""
PLATE_NAME_ID=""
PLATE_LINKED="false"

PLATE_ID=$(opencad_db_query "SELECT id FROM ncic_plates WHERE UPPER(REPLACE(veh_plate,'-','')) LIKE '%LAM8844%' AND id > ${BASELINE_NCIC_PLATE} ORDER BY id DESC LIMIT 1")
if [ -z "$PLATE_ID" ]; then
    PLATE_ID=$(opencad_db_query "SELECT id FROM ncic_plates WHERE UPPER(veh_plate) LIKE '%LAM%' AND id > ${BASELINE_NCIC_PLATE} ORDER BY id DESC LIMIT 1")
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

# --- WARRANT (must be linked to the new civilian) ---
WARRANT_ID=""
WARRANT_FOUND="false"
WARRANT_NAME=""
WARRANT_AGENCY=""
WARRANT_STATUS=""

if [ -n "$CIV_ID" ]; then
    WARRANT_ID=$(opencad_db_query "SELECT id FROM ncic_warrants WHERE name_id=${CIV_ID} AND id > ${BASELINE_NCIC_WARRANT} ORDER BY id DESC LIMIT 1")
fi
if [ -z "$WARRANT_ID" ]; then
    WARRANT_ID=$(opencad_db_query "SELECT id FROM ncic_warrants WHERE id > ${BASELINE_NCIC_WARRANT} ORDER BY id DESC LIMIT 1")
fi

if [ -n "$WARRANT_ID" ]; then
    WARRANT_FOUND="true"
    WARRANT_NAME=$(opencad_db_query "SELECT COALESCE(warrant_name,'') FROM ncic_warrants WHERE id=${WARRANT_ID}")
    WARRANT_AGENCY=$(opencad_db_query "SELECT COALESCE(issuing_agency,'') FROM ncic_warrants WHERE id=${WARRANT_ID}")
    WARRANT_STATUS=$(opencad_db_query "SELECT COALESCE(status,'') FROM ncic_warrants WHERE id=${WARRANT_ID}")
fi

RESULT_JSON=$(cat << EOF
{
    "civilian_found": ${CIV_FOUND},
    "civilian": {
        "id": "$(json_escape "${CIV_ID}")",
        "name": "$(json_escape "${CIV_NAME}")",
        "dob": "$(json_escape "${CIV_DOB}")",
        "gender": "$(json_escape "${CIV_GENDER}")",
        "race": "$(json_escape "${CIV_RACE}")",
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
    "warrant_found": ${WARRANT_FOUND},
    "warrant": {
        "id": "$(json_escape "${WARRANT_ID}")",
        "warrant_name": "$(json_escape "${WARRANT_NAME}")",
        "issuing_agency": "$(json_escape "${WARRANT_AGENCY}")",
        "status": "$(json_escape "${WARRANT_STATUS}")"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_result "$RESULT_JSON" /tmp/new_resident_full_processing_result.json

echo "Result saved to /tmp/new_resident_full_processing_result.json"
cat /tmp/new_resident_full_processing_result.json
echo "=== Export complete ==="
