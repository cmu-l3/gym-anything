#!/bin/bash
# Setup script for Appointment Schedule Audit Task
echo "=== Setting up Appointment Schedule Audit Task ==="

source /workspace/scripts/task_utils.sh

# Patient identifiers (all existing patients in the system)
PATIENT_1="BAH000011"  # Emily Chen
PATIENT_2="BAH000010"  # Rosa Martinez
PATIENT_3="BAH000005"  # Priya Patel

# Wait for Bahmni to be ready
echo "[SETUP] Waiting for Bahmni services..."
if ! wait_for_bahmni 540; then
    echo "[ERROR] Bahmni did not start in time"
    exit 1
fi

# Get patient UUIDs
echo "[SETUP] Getting patient UUIDs..."
PATIENT_1_UUID=$(get_patient_uuid_by_identifier "${PATIENT_1}" 2>/dev/null)
PATIENT_2_UUID=$(get_patient_uuid_by_identifier "${PATIENT_2}" 2>/dev/null)
PATIENT_3_UUID=$(get_patient_uuid_by_identifier "${PATIENT_3}" 2>/dev/null)

if [ -z "$PATIENT_1_UUID" ] || [ -z "$PATIENT_2_UUID" ] || [ -z "$PATIENT_3_UUID" ]; then
    echo "[ERROR] Could not find one or more patients"
    echo "Patient 1 (${PATIENT_1}): ${PATIENT_1_UUID}"
    echo "Patient 2 (${PATIENT_2}): ${PATIENT_2_UUID}"
    echo "Patient 3 (${PATIENT_3}): ${PATIENT_3_UUID}"
    exit 1
fi

echo "[SETUP] Patient 1 (${PATIENT_1}): ${PATIENT_1_UUID}"
echo "[SETUP] Patient 2 (${PATIENT_2}): ${PATIENT_2_UUID}"
echo "[SETUP] Patient 3 (${PATIENT_3}): ${PATIENT_3_UUID}"

echo "$PATIENT_1_UUID" > /tmp/asa_patient1_uuid
echo "$PATIENT_2_UUID" > /tmp/asa_patient2_uuid
echo "$PATIENT_3_UUID" > /tmp/asa_patient3_uuid

# Calculate tomorrow's date at 9:00 AM
TOMORROW=$(date -d "+1 day" +%Y-%m-%d)
CONFLICT_TIME="${TOMORROW}T09:00:00.000+0000"
CONFLICT_TIME_END="${TOMORROW}T09:30:00.000+0000"
echo "$CONFLICT_TIME" > /tmp/asa_original_appointment_time
echo "$TOMORROW" > /tmp/asa_appointment_date

echo "[SETUP] Conflict time: ${CONFLICT_TIME}"

# Get appointment service UUID (General OPD)
echo "[SETUP] Getting appointment service..."
APPT_SERVICES=$(curl -skS -u superman:Admin123 \
    "https://localhost/openmrs/ws/rest/v1/appointmentscheduling/appointmentservice?v=default" 2>/dev/null || echo '{"results":[]}')
echo "$APPT_SERVICES" > /tmp/asa_services_raw.json

SERVICE_UUID=$(echo "$APPT_SERVICES" | python3 -c "
import sys, json
d = json.load(sys.stdin)
results = d.get('results', [])
# Prefer OPD/General
for r in results:
    name = r.get('name', '').lower()
    if 'opd' in name or 'general' in name or 'outpatient' in name:
        print(r['uuid'])
        break
else:
    if results:
        print(results[0]['uuid'])
" 2>/dev/null)

echo "[SETUP] Appointment service UUID: ${SERVICE_UUID}"
echo "$SERVICE_UUID" > /tmp/asa_service_uuid

# Get location UUID
LOCATION_UUID=$(openmrs_api_get "/location?v=default" 2>/dev/null | \
    python3 -c "
import sys, json
d = json.load(sys.stdin)
results = d.get('results', [])
if results:
    print(results[0]['uuid'])
" 2>/dev/null)

echo "[SETUP] Location UUID: ${LOCATION_UUID}"

# Create 3 conflicting appointments via Bahmni Appointments REST
echo "[SETUP] Creating conflicting appointments..."

create_appointment() {
    local patient_uuid="$1"
    local service_uuid="$2"
    local location_uuid="$3"
    local start_time="$4"
    local end_time="$5"

    APPT_PAYLOAD="{
        \"patientUuid\": \"${patient_uuid}\",
        \"serviceUuid\": \"${service_uuid}\",
        \"startDateTime\": \"${start_time}\",
        \"endDateTime\": \"${end_time}\",
        \"appointmentKind\": \"Scheduled\",
        \"status\": \"Scheduled\",
        \"locationUuid\": \"${location_uuid}\"
    }"

    curl -skS -X POST \
        -H "Content-Type: application/json" \
        -u superman:Admin123 \
        "https://localhost/openmrs/ws/rest/v1/appointments" \
        -d "$APPT_PAYLOAD" 2>/dev/null
}

APPT_1_RESP=$(create_appointment "$PATIENT_1_UUID" "$SERVICE_UUID" "$LOCATION_UUID" "$CONFLICT_TIME" "$CONFLICT_TIME_END")
APPT_1_UUID=$(echo "$APPT_1_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('uuid',''))" 2>/dev/null)

APPT_2_RESP=$(create_appointment "$PATIENT_2_UUID" "$SERVICE_UUID" "$LOCATION_UUID" "$CONFLICT_TIME" "$CONFLICT_TIME_END")
APPT_2_UUID=$(echo "$APPT_2_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('uuid',''))" 2>/dev/null)

APPT_3_RESP=$(create_appointment "$PATIENT_3_UUID" "$SERVICE_UUID" "$LOCATION_UUID" "$CONFLICT_TIME" "$CONFLICT_TIME_END")
APPT_3_UUID=$(echo "$APPT_3_RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('uuid',''))" 2>/dev/null)

echo "[SETUP] Appointment 1 (Emily Chen): ${APPT_1_UUID}"
echo "[SETUP] Appointment 2 (Rosa Martinez): ${APPT_2_UUID}"
echo "[SETUP] Appointment 3 (Priya Patel): ${APPT_3_UUID}"

echo "$APPT_1_UUID" > /tmp/asa_appt1_uuid
echo "$APPT_2_UUID" > /tmp/asa_appt2_uuid
echo "$APPT_3_UUID" > /tmp/asa_appt3_uuid

if [ -z "$APPT_1_UUID" ] || [ -z "$APPT_2_UUID" ] || [ -z "$APPT_3_UUID" ]; then
    echo "[WARN] Some appointments may not have been created. Continuing..."
    echo "APPT_1 response: $APPT_1_RESP"
fi

# Record timestamp
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/asa_start_time

# Launch browser to Appointments module
APPT_URL="${BAHMNI_BASE_URL}/bahmni/appointments"
if ! restart_firefox "${BAHMNI_LOGIN_URL}" 5; then
    echo "[WARN] Browser launch had issues, continuing..."
fi

take_screenshot /tmp/task_start.png

echo "[SETUP] Conflict appointments created for ${TOMORROW} at 09:00"
echo "[SETUP] Patients: ${PATIENT_1} (Emily Chen), ${PATIENT_2} (Rosa Martinez), ${PATIENT_3} (Priya Patel)"
echo "=== Setup Complete ==="
