#!/bin/bash
echo "=== Exporting armed_carjacking_investigation result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

# Read baselines
BASELINE_ACTIVE=$(cat /tmp/aci_baseline_active_call 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_HISTORY=$(cat /tmp/aci_baseline_history_call 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_WARRANT=$(cat /tmp/aci_baseline_warrant 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_CITATION=$(cat /tmp/aci_baseline_citation 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_BOLO_VEH=$(cat /tmp/aci_baseline_bolo_veh 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_BOLO_PER=$(cat /tmp/aci_baseline_bolo_per 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_NCIC_NAME=$(cat /tmp/aci_baseline_ncic_name 2>/dev/null | tr -cd '0-9' || echo "0")
DEREK_ID=$(cat /tmp/aci_derek_id 2>/dev/null | tr -cd '0-9' || echo "0")
BASELINE_ACTIVE=${BASELINE_ACTIVE:-0}
BASELINE_HISTORY=${BASELINE_HISTORY:-0}
BASELINE_WARRANT=${BASELINE_WARRANT:-0}
BASELINE_CITATION=${BASELINE_CITATION:-0}
BASELINE_BOLO_VEH=${BASELINE_BOLO_VEH:-0}
BASELINE_BOLO_PER=${BASELINE_BOLO_PER:-0}
BASELINE_NCIC_NAME=${BASELINE_NCIC_NAME:-0}
DEREK_ID=${DEREK_ID:-0}

# ============================================================
# SECTION 1: DISPATCH CALL (10-31)
# ============================================================
CALL_ID=""
CALL_FOUND="false"
CALL_TYPE=""
CALL_PRIMARY=""
CALL_STREET1=""
CALL_STREET2=""
CALL_NARRATIVE=""

# Try 10-31 first, then any new call
CALL_ID=$(opencad_db_query "SELECT call_id FROM calls WHERE call_type LIKE '%10-31%' AND call_id > ${BASELINE_ACTIVE} ORDER BY call_id DESC LIMIT 1")
if [ -z "$CALL_ID" ]; then
    CALL_ID=$(opencad_db_query "SELECT call_id FROM call_history WHERE call_type LIKE '%10-31%' AND call_id > ${BASELINE_HISTORY} ORDER BY call_id DESC LIMIT 1")
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

# ============================================================
# SECTION 2: WARRANT FOR SUSPECT 1 (Derek Lawson)
# ============================================================
S1_WARRANT_ID=""
S1_WARRANT_FOUND="false"
S1_WARRANT_NAME_ID=""
S1_WARRANT_NAME=""
S1_WARRANT_AGENCY=""
S1_DEREK_WARRANT="false"

# Prefer warrant linked to Derek Lawson; fall back to any new warrant not linked to Ricky
S1_WARRANT_ID=$(opencad_db_query "SELECT id FROM ncic_warrants WHERE name_id=${DEREK_ID} AND id > ${BASELINE_WARRANT} ORDER BY id DESC LIMIT 1")
if [ -z "$S1_WARRANT_ID" ]; then
    S1_WARRANT_ID=$(opencad_db_query "SELECT id FROM ncic_warrants WHERE id > ${BASELINE_WARRANT} AND LOWER(warrant_name) LIKE '%carjacking%' ORDER BY id ASC LIMIT 1")
fi
if [ -z "$S1_WARRANT_ID" ]; then
    S1_WARRANT_ID=$(opencad_db_query "SELECT id FROM ncic_warrants WHERE id > ${BASELINE_WARRANT} ORDER BY id ASC LIMIT 1")
fi

if [ -n "$S1_WARRANT_ID" ]; then
    S1_WARRANT_FOUND="true"
    S1_WARRANT_NAME_ID=$(opencad_db_query "SELECT COALESCE(name_id,'') FROM ncic_warrants WHERE id=${S1_WARRANT_ID}")
    S1_WARRANT_NAME=$(opencad_db_query "SELECT COALESCE(warrant_name,'') FROM ncic_warrants WHERE id=${S1_WARRANT_ID}")
    S1_WARRANT_AGENCY=$(opencad_db_query "SELECT COALESCE(issuing_agency,'') FROM ncic_warrants WHERE id=${S1_WARRANT_ID}")
    if [ "${S1_WARRANT_NAME_ID}" = "${DEREK_ID}" ]; then
        S1_DEREK_WARRANT="true"
    fi
fi

# ============================================================
# SECTION 3: CITATION FOR SUSPECT 1 (Derek Lawson)
# ============================================================
S1_CITATION_ID=""
S1_CITATION_FOUND="false"
S1_CITATION_NAME_ID=""
S1_CITATION_NAME=""
S1_CITATION_FINE=""
S1_DEREK_CITATION="false"

S1_CITATION_ID=$(opencad_db_query "SELECT id FROM ncic_citations WHERE name_id=${DEREK_ID} AND id > ${BASELINE_CITATION} ORDER BY id DESC LIMIT 1")
if [ -z "$S1_CITATION_ID" ]; then
    S1_CITATION_ID=$(opencad_db_query "SELECT id FROM ncic_citations WHERE id > ${BASELINE_CITATION} ORDER BY id ASC LIMIT 1")
fi

if [ -n "$S1_CITATION_ID" ]; then
    S1_CITATION_FOUND="true"
    S1_CITATION_NAME_ID=$(opencad_db_query "SELECT COALESCE(name_id,'') FROM ncic_citations WHERE id=${S1_CITATION_ID}")
    S1_CITATION_NAME=$(opencad_db_query "SELECT COALESCE(citation_name,'') FROM ncic_citations WHERE id=${S1_CITATION_ID}")
    S1_CITATION_FINE=$(opencad_db_query "SELECT COALESCE(citation_fine,'0') FROM ncic_citations WHERE id=${S1_CITATION_ID}")
    if [ "${S1_CITATION_NAME_ID}" = "${DEREK_ID}" ]; then
        S1_DEREK_CITATION="true"
    fi
fi

# ============================================================
# SECTION 4: VEHICLE BOLO (stolen vehicle VIN-4477)
# ============================================================
VEH_BOLO_ID=""
VEH_BOLO_FOUND="false"
VEH_BOLO_MAKE=""
VEH_BOLO_MODEL=""
VEH_BOLO_PLATE=""
VEH_BOLO_COLOR=""
VEH_BOLO_REASON=""

VEH_BOLO_ID=$(opencad_db_query "SELECT id FROM bolos_vehicles WHERE UPPER(REPLACE(vehicle_plate,'-','')) LIKE '%VIN4477%' AND id > ${BASELINE_BOLO_VEH} ORDER BY id DESC LIMIT 1")
if [ -z "$VEH_BOLO_ID" ]; then
    VEH_BOLO_ID=$(opencad_db_query "SELECT id FROM bolos_vehicles WHERE UPPER(vehicle_plate) LIKE '%VIN%' AND id > ${BASELINE_BOLO_VEH} ORDER BY id DESC LIMIT 1")
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
# SECTION 5: NEW CIVILIAN (Ricky Alvarez)
# ============================================================
S2_CIV_ID=""
S2_CIV_FOUND="false"
S2_CIV_NAME=""
S2_CIV_DOB=""
S2_CIV_GENDER=""
S2_CIV_RACE=""
S2_CIV_DL=""

S2_CIV_ID=$(opencad_db_query "SELECT id FROM ncic_names WHERE LOWER(name) LIKE '%ricky%' AND LOWER(name) LIKE '%alvarez%' AND id > ${BASELINE_NCIC_NAME} ORDER BY id DESC LIMIT 1")
if [ -z "$S2_CIV_ID" ]; then
    S2_CIV_ID=$(opencad_db_query "SELECT id FROM ncic_names WHERE LOWER(name) LIKE '%alvarez%' AND id > ${BASELINE_NCIC_NAME} ORDER BY id DESC LIMIT 1")
fi
if [ -z "$S2_CIV_ID" ]; then
    S2_CIV_ID=$(opencad_db_query "SELECT id FROM ncic_names WHERE id > ${BASELINE_NCIC_NAME} ORDER BY id DESC LIMIT 1")
fi

if [ -n "$S2_CIV_ID" ]; then
    S2_CIV_FOUND="true"
    S2_CIV_NAME=$(opencad_db_query "SELECT COALESCE(name,'') FROM ncic_names WHERE id=${S2_CIV_ID}")
    S2_CIV_DOB=$(opencad_db_query "SELECT COALESCE(dob,'') FROM ncic_names WHERE id=${S2_CIV_ID}")
    S2_CIV_GENDER=$(opencad_db_query "SELECT COALESCE(gender,'') FROM ncic_names WHERE id=${S2_CIV_ID}")
    S2_CIV_RACE=$(opencad_db_query "SELECT COALESCE(race,'') FROM ncic_names WHERE id=${S2_CIV_ID}")
    S2_CIV_DL=$(opencad_db_query "SELECT COALESCE(dl_status,'') FROM ncic_names WHERE id=${S2_CIV_ID}")
fi

# ============================================================
# SECTION 6: PERSON BOLO (Ricky Alvarez)
# ============================================================
S2_BOLO_ID=""
S2_BOLO_FOUND="false"
S2_BOLO_FIRST=""
S2_BOLO_LAST=""
S2_BOLO_GENDER=""
S2_BOLO_DESC=""
S2_BOLO_REASON=""

# Find the newest person BOLO after baseline
S2_BOLO_ID=$(opencad_db_query "SELECT id FROM bolos_persons WHERE id > ${BASELINE_BOLO_PER} ORDER BY id DESC LIMIT 1")
if [ -n "$S2_BOLO_ID" ]; then
    S2_BOLO_FOUND="true"
    S2_BOLO_FIRST=$(opencad_db_query "SELECT COALESCE(first_name,'') FROM bolos_persons WHERE id=${S2_BOLO_ID}")
    S2_BOLO_LAST=$(opencad_db_query "SELECT COALESCE(last_name,'') FROM bolos_persons WHERE id=${S2_BOLO_ID}")
    S2_BOLO_GENDER=$(opencad_db_query "SELECT COALESCE(gender,'') FROM bolos_persons WHERE id=${S2_BOLO_ID}")
    S2_BOLO_DESC=$(opencad_db_query "SELECT COALESCE(physical_description,'') FROM bolos_persons WHERE id=${S2_BOLO_ID}")
    S2_BOLO_REASON=$(opencad_db_query "SELECT COALESCE(reason_wanted,'') FROM bolos_persons WHERE id=${S2_BOLO_ID}")
fi

# ============================================================
# SECTION 7: WARRANT FOR SUSPECT 2 (Ricky Alvarez)
# ============================================================
S2_WARRANT_ID=""
S2_WARRANT_FOUND="false"
S2_WARRANT_NAME_ID=""
S2_WARRANT_NAME=""
S2_WARRANT_AGENCY=""
S2_RICKY_WARRANT="false"

# Prefer warrant linked to Ricky's new civilian ID
if [ -n "$S2_CIV_ID" ]; then
    S2_WARRANT_ID=$(opencad_db_query "SELECT id FROM ncic_warrants WHERE name_id=${S2_CIV_ID} AND id > ${BASELINE_WARRANT} ORDER BY id DESC LIMIT 1")
fi
# Fall back to second newest warrant (first one is presumably Derek's)
if [ -z "$S2_WARRANT_ID" ]; then
    S2_WARRANT_ID=$(opencad_db_query "SELECT id FROM ncic_warrants WHERE id > ${BASELINE_WARRANT} AND id != ${S1_WARRANT_ID:-0} ORDER BY id DESC LIMIT 1")
fi

if [ -n "$S2_WARRANT_ID" ]; then
    S2_WARRANT_FOUND="true"
    S2_WARRANT_NAME_ID=$(opencad_db_query "SELECT COALESCE(name_id,'') FROM ncic_warrants WHERE id=${S2_WARRANT_ID}")
    S2_WARRANT_NAME=$(opencad_db_query "SELECT COALESCE(warrant_name,'') FROM ncic_warrants WHERE id=${S2_WARRANT_ID}")
    S2_WARRANT_AGENCY=$(opencad_db_query "SELECT COALESCE(issuing_agency,'') FROM ncic_warrants WHERE id=${S2_WARRANT_ID}")
    if [ -n "$S2_CIV_ID" ] && [ "${S2_WARRANT_NAME_ID}" = "${S2_CIV_ID}" ]; then
        S2_RICKY_WARRANT="true"
    fi
fi

# ============================================================
# Build result JSON
# ============================================================
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
    "suspect1_warrant_found": ${S1_WARRANT_FOUND},
    "suspect1_derek_warrant": ${S1_DEREK_WARRANT},
    "suspect1_warrant": {
        "id": "$(json_escape "${S1_WARRANT_ID}")",
        "name_id": "$(json_escape "${S1_WARRANT_NAME_ID}")",
        "warrant_name": "$(json_escape "${S1_WARRANT_NAME}")",
        "issuing_agency": "$(json_escape "${S1_WARRANT_AGENCY}")"
    },
    "suspect1_citation_found": ${S1_CITATION_FOUND},
    "suspect1_derek_citation": ${S1_DEREK_CITATION},
    "suspect1_citation": {
        "id": "$(json_escape "${S1_CITATION_ID}")",
        "name_id": "$(json_escape "${S1_CITATION_NAME_ID}")",
        "citation_name": "$(json_escape "${S1_CITATION_NAME}")",
        "fine": "$(json_escape "${S1_CITATION_FINE}")"
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
    "suspect2_civilian_found": ${S2_CIV_FOUND},
    "suspect2_civilian": {
        "id": "$(json_escape "${S2_CIV_ID}")",
        "name": "$(json_escape "${S2_CIV_NAME}")",
        "dob": "$(json_escape "${S2_CIV_DOB}")",
        "gender": "$(json_escape "${S2_CIV_GENDER}")",
        "race": "$(json_escape "${S2_CIV_RACE}")",
        "dl_status": "$(json_escape "${S2_CIV_DL}")"
    },
    "suspect2_bolo_found": ${S2_BOLO_FOUND},
    "suspect2_bolo": {
        "id": "$(json_escape "${S2_BOLO_ID}")",
        "first_name": "$(json_escape "${S2_BOLO_FIRST}")",
        "last_name": "$(json_escape "${S2_BOLO_LAST}")",
        "gender": "$(json_escape "${S2_BOLO_GENDER}")",
        "physical_description": "$(json_escape "${S2_BOLO_DESC}")",
        "reason_wanted": "$(json_escape "${S2_BOLO_REASON}")"
    },
    "suspect2_warrant_found": ${S2_WARRANT_FOUND},
    "suspect2_ricky_warrant": ${S2_RICKY_WARRANT},
    "suspect2_warrant": {
        "id": "$(json_escape "${S2_WARRANT_ID}")",
        "name_id": "$(json_escape "${S2_WARRANT_NAME_ID}")",
        "warrant_name": "$(json_escape "${S2_WARRANT_NAME}")",
        "issuing_agency": "$(json_escape "${S2_WARRANT_AGENCY}")"
    },
    "derek_id": "${DEREK_ID}",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_result "$RESULT_JSON" /tmp/armed_carjacking_investigation_result.json

echo "Result saved to /tmp/armed_carjacking_investigation_result.json"
cat /tmp/armed_carjacking_investigation_result.json
echo "=== Export complete ==="
