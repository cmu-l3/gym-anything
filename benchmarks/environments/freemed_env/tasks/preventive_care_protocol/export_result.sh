#!/bin/bash
# Export result: preventive_care_protocol
# Patient: Sherill Botsford (ID 10)

echo "=== Exporting preventive_care_protocol Result ==="

source /workspace/scripts/task_utils.sh

PATIENT_ID=10

take_screenshot /tmp/preventive_care_protocol_end.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_VITALS=$(cat /tmp/pcp_initial_vitals 2>/dev/null || echo "0")
INITIAL_IMMUNIZATIONS=$(cat /tmp/pcp_initial_immunizations 2>/dev/null || echo "0")
INITIAL_NOTES=$(cat /tmp/pcp_initial_notes 2>/dev/null || echo "0")
INITIAL_APPOINTMENTS=$(cat /tmp/pcp_initial_appointments 2>/dev/null || echo "0")

python3 << PYEOF
import subprocess, json, sys

TASK_START = int("$TASK_START")
PATIENT_ID = $PATIENT_ID
INITIAL_VITALS = int("$INITIAL_VITALS")
INITIAL_IMMUNIZATIONS = int("$INITIAL_IMMUNIZATIONS")
INITIAL_NOTES = int("$INITIAL_NOTES")
INITIAL_APPOINTMENTS = int("$INITIAL_APPOINTMENTS")

def q(sql):
    r = subprocess.run(
        ['mysql', '-u', 'freemed', '-pfreemed', 'freemed', '-N', '-e', sql],
        capture_output=True, text=True
    )
    return r.stdout.strip()

# --- Vitals ---
vitals_raw = q(f"SELECT bp_systolic, bp_diastolic, heart_rate, temperature, weight, height FROM vitals WHERE patient={PATIENT_ID} ORDER BY id DESC LIMIT 1")
vitals = {"bp_systolic": 0, "bp_diastolic": 0, "heart_rate": 0, "temperature": 0.0, "weight": 0.0, "height": 0.0}
if vitals_raw:
    parts = vitals_raw.split('\t')
    try:
        vitals["bp_systolic"] = int(parts[0]) if len(parts) > 0 and parts[0].strip() else 0
        vitals["bp_diastolic"] = int(parts[1]) if len(parts) > 1 and parts[1].strip() else 0
        vitals["heart_rate"] = int(parts[2]) if len(parts) > 2 and parts[2].strip() else 0
        vitals["temperature"] = float(parts[3]) if len(parts) > 3 and parts[3].strip() else 0.0
        vitals["weight"] = float(parts[4]) if len(parts) > 4 and parts[4].strip() else 0.0
        vitals["height"] = float(parts[5]) if len(parts) > 5 and parts[5].strip() else 0.0
    except (ValueError, IndexError):
        pass

vitals_count = int(q(f"SELECT COUNT(*) FROM vitals WHERE patient={PATIENT_ID}") or "0")

# --- Immunizations ---
immun_raw = q(f"SELECT vaccine, dateof, lot_number, manufacturer FROM immunization WHERE patient={PATIENT_ID} ORDER BY id DESC LIMIT 10")
immunizations = []
if immun_raw:
    for line in immun_raw.split('\n'):
        if not line.strip():
            continue
        parts = line.split('\t')
        if len(parts) >= 1:
            immunizations.append({
                "vaccine": parts[0].strip() if len(parts) > 0 else "",
                "date": parts[1].strip() if len(parts) > 1 else "",
                "lot_number": parts[2].strip() if len(parts) > 2 else "",
                "manufacturer": parts[3].strip() if len(parts) > 3 else ""
            })

immun_count = int(q(f"SELECT COUNT(*) FROM immunization WHERE patient={PATIENT_ID}") or "0")

# --- Clinical notes ---
notes_raw = q(f"SELECT pnotetext FROM pnotes WHERE pnotespat={PATIENT_ID} ORDER BY id DESC LIMIT 1")
note_text = notes_raw.strip() if notes_raw else ""
notes_count = int(q(f"SELECT COUNT(*) FROM pnotes WHERE pnotespat={PATIENT_ID}") or "0")

# --- Appointments ---
appt_raw = q(f"SELECT caldateof, caltimeof, caldescription FROM scheduler WHERE calpatient={PATIENT_ID} ORDER BY id DESC LIMIT 10")
appointments = []
if appt_raw:
    for line in appt_raw.split('\n'):
        if not line.strip():
            continue
        parts = line.split('\t')
        appointments.append({
            "date": parts[0].strip() if len(parts) > 0 else "",
            "time": parts[1].strip() if len(parts) > 1 else "",
            "description": parts[2].strip() if len(parts) > 2 else ""
        })

appt_count = int(q(f"SELECT COUNT(*) FROM scheduler WHERE calpatient={PATIENT_ID}") or "0")

result = {
    "task_start": TASK_START,
    "patient_id": PATIENT_ID,
    "vitals": vitals,
    "vitals_count": vitals_count,
    "initial_vitals": INITIAL_VITALS,
    "immunizations": immunizations,
    "immun_count": immun_count,
    "initial_immunizations": INITIAL_IMMUNIZATIONS,
    "note_text": note_text,
    "notes_count": notes_count,
    "initial_notes": INITIAL_NOTES,
    "appointments": appointments,
    "appt_count": appt_count,
    "initial_appointments": INITIAL_APPOINTMENTS
}

with open("/tmp/preventive_care_protocol_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete.")
print(f"  Vitals count: {vitals_count} (initial: {INITIAL_VITALS})")
print(f"  Immunizations count: {immun_count} (initial: {INITIAL_IMMUNIZATIONS})")
print(f"  Immunizations: {[i['vaccine'] for i in immunizations]}")
print(f"  Notes count: {notes_count} (initial: {INITIAL_NOTES})")
print(f"  Appointments count: {appt_count} (initial: {INITIAL_APPOINTMENTS})")
PYEOF

echo "=== Export Complete ==="
