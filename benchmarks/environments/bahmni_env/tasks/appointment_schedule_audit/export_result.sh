#!/bin/bash
# Export script for Appointment Schedule Audit Task
echo "=== Exporting Appointment Schedule Audit Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

PATIENT_1_UUID=$(cat /tmp/asa_patient1_uuid 2>/dev/null || echo "")
PATIENT_2_UUID=$(cat /tmp/asa_patient2_uuid 2>/dev/null || echo "")
PATIENT_3_UUID=$(cat /tmp/asa_patient3_uuid 2>/dev/null || echo "")
TOMORROW=$(cat /tmp/asa_appointment_date 2>/dev/null || date -d "+1 day" +%Y-%m-%d)
ORIGINAL_TIME=$(cat /tmp/asa_original_appointment_time 2>/dev/null || echo "")
APPT_1_UUID=$(cat /tmp/asa_appt1_uuid 2>/dev/null || echo "")
APPT_2_UUID=$(cat /tmp/asa_appt2_uuid 2>/dev/null || echo "")
APPT_3_UUID=$(cat /tmp/asa_appt3_uuid 2>/dev/null || echo "")

# If setup files are missing, write error result and exit
if [ -z "$PATIENT_1_UUID" ] && [ -z "$PATIENT_2_UUID" ]; then
    cat > /tmp/appointment_schedule_audit_result.json << 'EOF'
{"error": "Setup files not found - setup_task.sh may not have completed", "appointments_found": 0, "patient_identifiers": ["BAH000011", "BAH000010", "BAH000005"]}
EOF
    echo "[EXPORT] Warning: Setup files missing, writing error result"
    echo "=== Export Complete ==="
    exit 0
fi

echo "[EXPORT] Getting appointments for date: ${TOMORROW}"
echo "[EXPORT] Original conflict time: ${ORIGINAL_TIME}"

# Query all appointments for tomorrow
APPTS_RESP=$(curl -skS -u superman:Admin123 \
    "https://localhost/openmrs/ws/rest/v1/appointments/all?forDate=${TOMORROW}T00:00:00.000Z&v=full" 2>/dev/null || echo '[]')
echo "$APPTS_RESP" > /tmp/asa_all_appointments_raw.json

# Also try alternate endpoint
APPTS_RESP2=$(curl -skS -u superman:Admin123 \
    "https://localhost/openmrs/ws/rest/v1/appointments?forDate=${TOMORROW}&v=full" 2>/dev/null || echo '{"results":[]}')
echo "$APPTS_RESP2" > /tmp/asa_all_appointments_raw2.json

# Get specific appointments by UUID if we have them
if [ -n "$APPT_1_UUID" ]; then
    curl -skS -u superman:Admin123 \
        "https://localhost/openmrs/ws/rest/v1/appointments/${APPT_1_UUID}?v=full" 2>/dev/null > /tmp/asa_appt1_detail.json
fi
if [ -n "$APPT_2_UUID" ]; then
    curl -skS -u superman:Admin123 \
        "https://localhost/openmrs/ws/rest/v1/appointments/${APPT_2_UUID}?v=full" 2>/dev/null > /tmp/asa_appt2_detail.json
fi
if [ -n "$APPT_3_UUID" ]; then
    curl -skS -u superman:Admin123 \
        "https://localhost/openmrs/ws/rest/v1/appointments/${APPT_3_UUID}?v=full" 2>/dev/null > /tmp/asa_appt3_detail.json
fi

# Query appointments DB directly
echo "[EXPORT] Querying appointments from database..."
DB_APPTS=$(docker exec bahmni-openmrsdb mysql -u openmrs-user -ppassword openmrs -N -e "
SELECT a.uuid, pi.identifier, p.given_name, p.family_name,
       a.start_date_time, a.end_date_time, a.status, a.voided
FROM appointmentscheduling_appointment a
JOIN patient_identifier pi ON a.patient_id = pi.patient_id
JOIN person_name p ON a.patient_id = p.person_id
WHERE pi.identifier IN ('BAH000011', 'BAH000010', 'BAH000005')
AND DATE(a.start_date_time) = '${TOMORROW}'
AND a.voided = 0
ORDER BY a.start_date_time ASC;
" 2>/dev/null || echo "TABLE_NOT_FOUND")

echo "$DB_APPTS" > /tmp/asa_db_appointments.txt

python3 << 'PYEOF'
import json
import os
from datetime import datetime, timezone

def read_file(path, default=''):
    try:
        return open(path).read().strip()
    except:
        return default

patient_1_uuid = read_file('/tmp/asa_patient1_uuid')
patient_2_uuid = read_file('/tmp/asa_patient2_uuid')
patient_3_uuid = read_file('/tmp/asa_patient3_uuid')
original_time_str = read_file('/tmp/asa_original_appointment_time')
appt_1_uuid = read_file('/tmp/asa_appt1_uuid')
appt_2_uuid = read_file('/tmp/asa_appt2_uuid')
appt_3_uuid = read_file('/tmp/asa_appt3_uuid')
tomorrow = read_file('/tmp/asa_appointment_date', 'unknown')

# Parse original conflict time
try:
    # Handle both formats
    orig_str = original_time_str.replace('+0000', '+00:00').replace('Z', '+00:00')
    original_dt = datetime.fromisoformat(orig_str)
    original_hour = original_dt.hour
    original_minute = original_dt.minute
except:
    original_hour = 9
    original_minute = 0

# Load all appointment data
appointments_by_patient = {
    'BAH000011': None,  # Emily Chen
    'BAH000010': None,  # Rosa Martinez
    'BAH000005': None,  # Priya Patel
}

def parse_appt_time(time_str):
    """Parse appointment time and return hour, minute tuple."""
    if not time_str:
        return None, None
    try:
        ts = time_str.replace('Z', '+00:00').replace('+0000', '+00:00')
        dt = datetime.fromisoformat(ts)
        return dt.hour, dt.minute
    except:
        # Try simple parsing
        try:
            if 'T' in time_str:
                time_part = time_str.split('T')[1][:8]
                parts = time_part.split(':')
                return int(parts[0]), int(parts[1])
        except:
            pass
    return None, None

# Try to get specific appointment details
appt_details = {}
for uuid_var, id_key in [(appt_1_uuid, 'BAH000011'), (appt_2_uuid, 'BAH000010'), (appt_3_uuid, 'BAH000005')]:
    if not uuid_var:
        continue
    fname = f'/tmp/asa_appt{["BAH000011","BAH000010","BAH000005"].index(id_key)+1}_detail.json'
    if os.path.exists(fname):
        try:
            with open(fname) as f:
                data = json.load(f)
            start = data.get('startDateTime', '')
            hour, minute = parse_appt_time(start)
            if hour is not None:
                appt_details[id_key] = {'start_hour': hour, 'start_minute': minute,
                                        'status': data.get('status', ''), 'uuid': uuid_var,
                                        'raw_start': start}
        except:
            pass

# Try database results
db_text = open('/tmp/asa_db_appointments.txt').read().strip()
if db_text and db_text != 'TABLE_NOT_FOUND':
    for line in db_text.split('\n'):
        if not line.strip():
            continue
        parts = line.split('\t')
        if len(parts) >= 7:
            uuid = parts[0].strip()
            identifier = parts[1].strip()
            start_time = parts[4].strip()
            status = parts[6].strip()
            if identifier in appointments_by_patient:
                hour, minute = parse_appt_time(start_time)
                if hour is not None:
                    appt_details[identifier] = {
                        'start_hour': hour,
                        'start_minute': minute,
                        'status': status,
                        'uuid': uuid,
                        'raw_start': start_time
                    }

# Analyze results
emily_appt = appt_details.get('BAH000011', {})
rosa_appt = appt_details.get('BAH000010', {})
priya_appt = appt_details.get('BAH000005', {})

def time_diff_minutes(hour, minute):
    """Minutes difference from original conflict time."""
    if hour is None:
        return None
    return (hour - original_hour) * 60 + (minute - original_minute)

emily_diff = time_diff_minutes(emily_appt.get('start_hour'), emily_appt.get('start_minute'))
rosa_diff = time_diff_minutes(rosa_appt.get('start_hour'), rosa_appt.get('start_minute'))
priya_diff = time_diff_minutes(priya_appt.get('start_hour'), priya_appt.get('start_minute'))

# Evaluate correctness
TOLERANCE_MINUTES = 20  # Allow ±20 min tolerance

# Emily should be ~60 min later
emily_correct = emily_diff is not None and (60 - TOLERANCE_MINUTES) <= emily_diff <= (60 + TOLERANCE_MINUTES)
emily_changed = emily_diff is not None and emily_diff != 0

# Rosa should be ~120 min later
rosa_correct = rosa_diff is not None and (120 - TOLERANCE_MINUTES) <= rosa_diff <= (120 + TOLERANCE_MINUTES)
rosa_changed = rosa_diff is not None and rosa_diff != 0

# Priya should be unchanged (0 diff)
priya_unchanged = priya_diff is not None and abs(priya_diff) <= TOLERANCE_MINUTES

# All three at different times
times_set = set()
all_different = True
for appt in [emily_appt, rosa_appt, priya_appt]:
    h = appt.get('start_hour')
    m = appt.get('start_minute')
    if h is not None:
        time_key = h * 60 + m
        if time_key in times_set:
            all_different = False
        times_set.add(time_key)

result = {
    "patient_identifiers": ["BAH000011", "BAH000010", "BAH000005"],
    "original_conflict_hour": original_hour,
    "original_conflict_minute": original_minute,
    "emily_chen": {
        "identifier": "BAH000011",
        "start_hour": emily_appt.get('start_hour'),
        "start_minute": emily_appt.get('start_minute'),
        "diff_from_original_minutes": emily_diff,
        "correctly_rescheduled_plus_1hr": emily_correct,
        "was_changed": emily_changed,
        "raw_start": emily_appt.get('raw_start', '')
    },
    "rosa_martinez": {
        "identifier": "BAH000010",
        "start_hour": rosa_appt.get('start_hour'),
        "start_minute": rosa_appt.get('start_minute'),
        "diff_from_original_minutes": rosa_diff,
        "correctly_rescheduled_plus_2hr": rosa_correct,
        "was_changed": rosa_changed,
        "raw_start": rosa_appt.get('raw_start', '')
    },
    "priya_patel": {
        "identifier": "BAH000005",
        "start_hour": priya_appt.get('start_hour'),
        "start_minute": priya_appt.get('start_minute'),
        "diff_from_original_minutes": priya_diff,
        "appointment_unchanged": priya_unchanged,
        "raw_start": priya_appt.get('raw_start', '')
    },
    "all_different_times": all_different,
    "appointments_found": len(appt_details),
    "db_result_raw": db_text[:500] if db_text and db_text != 'TABLE_NOT_FOUND' else db_text
}

with open('/tmp/appointment_schedule_audit_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"[EXPORT] Emily diff: {emily_diff} min (correct: {emily_correct})")
print(f"[EXPORT] Rosa diff: {rosa_diff} min (correct: {rosa_correct})")
print(f"[EXPORT] Priya unchanged: {priya_unchanged}")
print(f"[EXPORT] All different times: {all_different}")
PYEOF

echo "[EXPORT] Result saved to /tmp/appointment_schedule_audit_result.json"
cat /tmp/appointment_schedule_audit_result.json | python3 -m json.tool > /dev/null 2>&1 && echo "[EXPORT] JSON valid"

echo "=== Export Complete ==="
