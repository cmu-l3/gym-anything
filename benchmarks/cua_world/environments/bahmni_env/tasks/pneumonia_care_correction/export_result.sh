#!/bin/bash
echo "=== Exporting pneumonia_care_correction results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Read saved state from setup
PATIENT_UUID=$(cat /tmp/pcc_patient_uuid.txt 2>/dev/null || echo "")
PATIENT_ID=$(cat /tmp/pcc_patient_identifier.txt 2>/dev/null || echo "BAH000030")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_ENC=$(cat /tmp/pcc_initial_encounter_count.txt 2>/dev/null || echo "0")
INITIAL_OBS=$(cat /tmp/pcc_initial_obs_count.txt 2>/dev/null || echo "0")
INITIAL_ORD=$(cat /tmp/pcc_initial_order_count.txt 2>/dev/null || echo "0")
INITIAL_ALG=$(cat /tmp/pcc_initial_allergy_count.txt 2>/dev/null || echo "0")

if [ -z "$PATIENT_UUID" ]; then
    echo "WARNING: Patient UUID not found, attempting recovery..."
    PATIENT_UUID=$(get_patient_uuid_by_identifier "$PATIENT_ID")
fi

if [ -z "$PATIENT_UUID" ]; then
    echo "ERROR: Could not find patient UUID"
    echo '{"error": "patient_not_found"}' > /tmp/pneumonia_care_result.json
    chmod 666 /tmp/pneumonia_care_result.json
    exit 0
fi

echo "Patient UUID: $PATIENT_UUID"
echo "Task start time: $TASK_START"

# 3. Query current state via REST API
echo "Fetching encounters..."
ENCOUNTERS_JSON=$(openmrs_api_get "/encounter?patient=${PATIENT_UUID}&v=full")
echo "$ENCOUNTERS_JSON" > /tmp/pcc_encounters_raw.json

echo "Fetching observations..."
OBS_JSON=$(openmrs_api_get "/obs?patient=${PATIENT_UUID}&v=full")
echo "$OBS_JSON" > /tmp/pcc_obs_raw.json

echo "Fetching drug orders (including voided)..."
ORDERS_JSON=$(openmrs_api_get "/order?patient=${PATIENT_UUID}&t=drugorder&v=full")
echo "$ORDERS_JSON" > /tmp/pcc_orders_raw.json

echo "Fetching allergies..."
ALLERGIES_JSON=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
    "${OPENMRS_API_URL}/patient/${PATIENT_UUID}/allergy?v=full" 2>/dev/null || echo "[]")
echo "$ALLERGIES_JSON" > /tmp/pcc_allergies_raw.json

echo "Fetching diagnoses via Bahmni API..."
DIAGNOSES_JSON=$(openmrs_api_get "/bahmnicore/diagnosis/search?patientUuid=${PATIENT_UUID}")
echo "$DIAGNOSES_JSON" > /tmp/pcc_diagnoses_raw.json

# 4. Query diagnoses and order status via MySQL (more reliable)
echo "Querying MySQL for diagnoses..."
MYSQL_DIAGNOSES=$(docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -N -e "
    SELECT
        cn.name AS diagnosis_name,
        ed.diagnosis_certainty,
        ed.rank,
        e.encounter_datetime
    FROM encounter_diagnosis ed
    JOIN encounter e ON ed.encounter_id = e.encounter_id
    JOIN concept_name cn ON ed.diagnosis_coded = cn.concept_id
        AND cn.concept_name_type = 'FULLY_SPECIFIED' AND cn.voided = 0
    JOIN patient_identifier pi ON e.patient_id = pi.patient_id
    WHERE pi.identifier = '${PATIENT_ID}'
        AND ed.voided = 0
    ORDER BY e.encounter_datetime DESC;
" 2>/dev/null || echo "")
echo "$MYSQL_DIAGNOSES" > /tmp/pcc_mysql_diagnoses.txt

echo "Querying MySQL for order status..."
MYSQL_ORDERS=$(docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -N -e "
    SELECT
        d.name AS drug_name,
        o.order_action,
        o.voided,
        o.date_stopped,
        o.date_created,
        cn.name AS concept_name
    FROM orders o
    LEFT JOIN drug_order dro ON o.order_id = dro.order_id
    LEFT JOIN drug d ON dro.drug_inventory_id = d.drug_id
    LEFT JOIN concept_name cn ON o.concept_id = cn.concept_id
        AND cn.concept_name_type = 'FULLY_SPECIFIED' AND cn.voided = 0
    JOIN patient_identifier pi ON o.patient_id = pi.patient_id
    WHERE pi.identifier = '${PATIENT_ID}'
    ORDER BY o.date_created DESC;
" 2>/dev/null || echo "")
echo "$MYSQL_ORDERS" > /tmp/pcc_mysql_orders.txt

# 5. Query appointments for follow-up window (5-9 days from now)
echo "Fetching appointments..."
FOLLOW_UP_START=$(date -d "+5 days" +%Y-%m-%d 2>/dev/null || date -v+5d +%Y-%m-%d 2>/dev/null || echo "")
FOLLOW_UP_END=$(date -d "+9 days" +%Y-%m-%d 2>/dev/null || date -v+9d +%Y-%m-%d 2>/dev/null || echo "")

APPOINTMENTS_JSON="[]"
if [ -n "$FOLLOW_UP_START" ] && [ -n "$FOLLOW_UP_END" ]; then
    APPOINTMENTS_JSON=$(curl -sk -u "${BAHMNI_ADMIN_USERNAME}:${BAHMNI_ADMIN_PASSWORD}" \
        -H "Content-Type: application/json" \
        "${OPENMRS_API_URL}/appointments/search" \
        -X POST -d "{\"patientUuid\": \"${PATIENT_UUID}\", \"startDate\": \"${FOLLOW_UP_START}\", \"endDate\": \"${FOLLOW_UP_END}\"}" \
        2>/dev/null || echo "[]")
fi
echo "$APPOINTMENTS_JSON" > /tmp/pcc_appointments_raw.json

# 6. Assemble result JSON via Python
python3 << 'PYEOF'
import json
import sys
import os
from datetime import datetime

def safe_load(path, default=None):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return default if default is not None else {}

def safe_read(path, default=""):
    try:
        with open(path) as f:
            return f.read().strip()
    except Exception:
        return default

# Load raw API responses
encounters = safe_load("/tmp/pcc_encounters_raw.json", {})
obs_data = safe_load("/tmp/pcc_obs_raw.json", {})
orders_data = safe_load("/tmp/pcc_orders_raw.json", {})
allergies_data = safe_load("/tmp/pcc_allergies_raw.json", [])
diagnoses_data = safe_load("/tmp/pcc_diagnoses_raw.json", [])
appointments_data = safe_load("/tmp/pcc_appointments_raw.json", [])

task_start = int(safe_read("/tmp/task_start_time.txt", "0"))
patient_uuid = safe_read("/tmp/pcc_patient_uuid.txt")
patient_id = safe_read("/tmp/pcc_patient_identifier.txt", "BAH000030")
mysql_diagnoses = safe_read("/tmp/pcc_mysql_diagnoses.txt")
mysql_orders = safe_read("/tmp/pcc_mysql_orders.txt")

# Parse encounters
enc_list = encounters.get("results", []) if isinstance(encounters, dict) else []

# Parse observations - extract vitals
obs_list = obs_data.get("results", []) if isinstance(obs_data, dict) else []

# CIEL concept UUIDs
CONCEPT_MAP = {
    "5089AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA": "weight",
    "5090AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA": "height",
    "5087AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA": "pulse",
    "5088AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA": "temperature",
    "5085AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA": "systolic_bp",
    "5086AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA": "diastolic_bp",
    "5242AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA": "respiratory_rate",
    "5092AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA": "spo2",
}

vitals = {}
all_weight_obs = []
for ob in obs_list:
    concept = ob.get("concept", {})
    concept_uuid = concept.get("uuid", "")
    vital_name = CONCEPT_MAP.get(concept_uuid)
    if vital_name:
        val = ob.get("value")
        if isinstance(val, dict):
            val = val.get("display", val.get("name", ""))
        obs_time = ob.get("obsDatetime", "")
        voided = ob.get("voided", False)

        if vital_name == "weight":
            all_weight_obs.append({
                "value": val,
                "datetime": obs_time,
                "voided": voided,
                "uuid": ob.get("uuid", "")
            })

        if not voided:
            if vital_name not in vitals:
                vitals[vital_name] = []
            vitals[vital_name].append({
                "value": val,
                "datetime": obs_time
            })

# Parse drug orders
order_list = orders_data.get("results", []) if isinstance(orders_data, dict) else []
drug_orders = []
amoxicillin_status = "unknown"
for o in order_list:
    display = o.get("display", "") or o.get("drug", {}).get("display", "")
    drug_name = ""
    if o.get("drug"):
        drug_name = o["drug"].get("display", o["drug"].get("name", ""))
    order_info = {
        "display": display,
        "drug_name": drug_name,
        "action": o.get("action", ""),
        "voided": o.get("voided", False),
        "date_stopped": o.get("dateStopped"),
        "uuid": o.get("uuid", ""),
        "date_activated": o.get("dateActivated", ""),
    }
    drug_orders.append(order_info)

    if "amoxicillin" in (drug_name or display).lower():
        if o.get("voided") or o.get("dateStopped") or o.get("action") == "DISCONTINUE":
            amoxicillin_status = "discontinued"
        else:
            amoxicillin_status = "active"

# Parse allergies
if isinstance(allergies_data, dict):
    allergy_list = allergies_data.get("results", [])
elif isinstance(allergies_data, list):
    allergy_list = allergies_data
else:
    allergy_list = []

allergy_count = len(allergy_list)

# Parse diagnoses
if isinstance(diagnoses_data, dict):
    diag_list = diagnoses_data.get("results", diagnoses_data)
elif isinstance(diagnoses_data, list):
    diag_list = diagnoses_data
else:
    diag_list = []

diagnoses = []
for d in diag_list:
    coded = d.get("codedAnswer", {})
    name = coded.get("name", "") if coded else ""
    if not name:
        name = d.get("concept", {}).get("name", "")
    diagnoses.append({
        "name": name,
        "order": d.get("order", ""),
        "certainty": d.get("certainty", ""),
        "datetime": d.get("diagnosisDateTime", "")
    })

# Parse appointments
if isinstance(appointments_data, dict):
    appt_list = appointments_data.get("results", [])
elif isinstance(appointments_data, list):
    appt_list = appointments_data
else:
    appt_list = []

appointments = []
for a in appt_list:
    appointments.append({
        "start": a.get("startDateTime", ""),
        "end": a.get("endDateTime", ""),
        "status": a.get("status", ""),
        "service": a.get("service", {}).get("name", "") if a.get("service") else "",
        "uuid": a.get("uuid", "")
    })

# Find longest free-text observation (clinical note)
longest_note = ""
for ob in obs_list:
    val = ob.get("value")
    if isinstance(val, str) and len(val) > len(longest_note):
        if not ob.get("voided", False):
            longest_note = val

# Also check encounter obs for notes
for enc in enc_list:
    for ob in enc.get("obs", []):
        val = ob.get("value")
        if isinstance(val, str) and len(val) > len(longest_note):
            longest_note = val

# Check for disposition obs
disposition_value = ""
for ob in obs_list:
    concept = ob.get("concept", {})
    concept_name = concept.get("display", "").lower()
    if "disposition" in concept_name or "admit" in str(ob.get("value", "")).lower():
        val = ob.get("value")
        if isinstance(val, dict):
            disposition_value = val.get("display", str(val))
        elif isinstance(val, str):
            disposition_value = val
        if not ob.get("voided", False) and disposition_value:
            break

# Assemble final result
result = {
    "task_start_time": task_start,
    "patient_uuid": patient_uuid,
    "patient_identifier": patient_id,
    "vitals": vitals,
    "all_weight_observations": all_weight_obs,
    "drug_orders": drug_orders,
    "amoxicillin_status": amoxicillin_status,
    "allergy_count": allergy_count,
    "diagnoses": diagnoses,
    "mysql_diagnoses": mysql_diagnoses,
    "mysql_orders": mysql_orders,
    "appointments": appointments,
    "disposition": disposition_value,
    "clinical_note_length": len(longest_note),
    "clinical_note_preview": longest_note[:500] if longest_note else "",
    "encounter_count": len(enc_list),
    "initial_encounter_count": int(safe_read("/tmp/pcc_initial_encounter_count.txt", "0")),
    "initial_obs_count": int(safe_read("/tmp/pcc_initial_obs_count.txt", "0")),
    "initial_order_count": int(safe_read("/tmp/pcc_initial_order_count.txt", "0")),
    "initial_allergy_count": int(safe_read("/tmp/pcc_initial_allergy_count.txt", "0")),
}

with open("/tmp/pneumonia_care_result.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

print(f"Result exported: vitals={list(vitals.keys())}, orders={len(drug_orders)}, "
      f"diagnoses={len(diagnoses)}, appointments={len(appointments)}, "
      f"note_len={len(longest_note)}, amox_status={amoxicillin_status}")
PYEOF

chmod 666 /tmp/pneumonia_care_result.json 2>/dev/null || true
chmod 644 /tmp/task_final.png 2>/dev/null || true

echo "=== Export complete ==="
