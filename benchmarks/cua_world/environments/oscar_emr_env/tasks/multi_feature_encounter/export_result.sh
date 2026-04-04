#!/bin/bash
# Export script for Multi-Feature Encounter task in OSCAR EMR

echo "=== Exporting Multi-Feature Encounter Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

PATIENT_NO=$(cat /tmp/task_patient_no_multi 2>/dev/null || oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Robert' AND last_name='MacPherson' LIMIT 1")
INITIAL_MEASUREMENT_COUNT=$(cat /tmp/initial_measurement_count_multi 2>/dev/null || echo "0")
INITIAL_DRUG_COUNT=$(cat /tmp/initial_drug_count_multi 2>/dev/null || echo "0")
INITIAL_TICKLER_STATUS=$(cat /tmp/initial_tickler_status_multi 2>/dev/null || echo "A")
TICKLER_NO=$(cat /tmp/task_tickler_no_multi 2>/dev/null || echo "")

echo "Patient demographic_no: $PATIENT_NO"
echo "Seeded tickler_no: $TICKLER_NO"

python3 << PYEOF
import json, subprocess

patient_no = "${PATIENT_NO}"
initial_measurements = int("${INITIAL_MEASUREMENT_COUNT}".strip() or "0")
initial_drugs = int("${INITIAL_DRUG_COUNT}".strip() or "0")
initial_tickler_status = "${INITIAL_TICKLER_STATUS}".strip() or "A"
seeded_tickler_no = "${TICKLER_NO}".strip()

def run_query(q):
    try:
        r = subprocess.run(
            ['docker', 'exec', 'oscar-db', 'mysql', '-u', 'oscar', '-poscar', 'oscar', '-N', '-e', q],
            capture_output=True, text=True, timeout=15
        )
        return r.stdout.strip()
    except Exception:
        return ""

# Query measurements
current_measurements = int(run_query(f"SELECT COUNT(*) FROM measurements WHERE demographicNo={patient_no}") or "0")
meas_rows = run_query(f"SELECT type, dataField FROM measurements WHERE demographicNo={patient_no} ORDER BY id DESC")

# Analyze measurements
all_meas_types = []
all_meas_values = []
has_bp = False
bp_value = ""

for line in meas_rows.splitlines():
    parts = line.split('\t')
    if len(parts) >= 2:
        mtype = parts[0].strip()
        mval = parts[1].strip()
        all_meas_types.append(mtype)
        all_meas_values.append(mval)
        mtype_lower = mtype.lower()
        # Check for BP measurement
        if 'bp' in mtype_lower or 'blood' in mtype_lower or 'pressure' in mtype_lower:
            has_bp = True
            bp_value = mval
        # Also check if value looks like BP reading (systolic/diastolic pattern)
        if '/' in mval:
            parts2 = mval.split('/')
            if len(parts2) == 2:
                try:
                    sys_val = int(parts2[0].strip())
                    dia_val = int(parts2[1].strip())
                    if 70 <= sys_val <= 250 and 40 <= dia_val <= 150:
                        has_bp = True
                        bp_value = mval
                except ValueError:
                    pass

# Check if BP value is close to expected 158/92
bp_value_correct = False
if bp_value:
    try:
        parts2 = bp_value.split('/')
        if len(parts2) == 2:
            sys_val = int(parts2[0].strip())
            dia_val = int(parts2[1].strip())
            if 148 <= sys_val <= 168 and 82 <= dia_val <= 102:
                bp_value_correct = True
    except Exception:
        pass

# Query medications
current_active_drugs = int(run_query(f"SELECT COUNT(*) FROM drugs WHERE demographic_no={patient_no} AND archived=0") or "0")
ramipril_row = run_query(f"SELECT drugid, GN, dosage, freqcode, archived FROM drugs WHERE demographic_no={patient_no} AND (GN LIKE '%Ramipril%' OR BN LIKE '%Altace%') ORDER BY drugid DESC LIMIT 1")

ramipril_found = False
ramipril_active = False
ramipril_dose_ok = False
if ramipril_row:
    parts = ramipril_row.split('\t')
    ramipril_found = True
    dosage = parts[2].strip() if len(parts) > 2 else ''
    archived = parts[4].strip() if len(parts) > 4 else '1'
    ramipril_active = archived == '0'
    ramipril_dose_ok = '10' in dosage

# Query tickler status
tickler_current_status = ""
if seeded_tickler_no:
    tickler_current_status = run_query(f"SELECT status FROM tickler WHERE tickler_no={seeded_tickler_no} LIMIT 1")
else:
    tickler_current_status = run_query(f"SELECT status FROM tickler WHERE demographic_no={patient_no} ORDER BY tickler_no DESC LIMIT 1")

tickler_resolved = tickler_current_status.strip() in ('C', 'I', 'D') or tickler_current_status.strip() == 'c'
# If tickler row is gone (deleted), also consider it resolved
if not tickler_current_status:
    all_ticklers = run_query(f"SELECT COUNT(*) FROM tickler WHERE demographic_no={patient_no}")
    if int(all_ticklers or "0") == 0:
        tickler_resolved = True

new_measurements = current_measurements - initial_measurements
new_drugs = current_active_drugs - initial_drugs

result = {
    "patient_no": patient_no,
    "patient_fname": "Robert",
    "patient_lname": "MacPherson",
    "initial_measurement_count": initial_measurements,
    "current_measurement_count": current_measurements,
    "new_measurement_count": new_measurements,
    "measurement_types": all_meas_types,
    "measurement_values": all_meas_values,
    "has_bp_measurement": has_bp,
    "bp_value": bp_value,
    "bp_value_approx_correct": bp_value_correct,
    "initial_drug_count": initial_drugs,
    "current_active_drugs": current_active_drugs,
    "new_drug_count": new_drugs,
    "ramipril_found": ramipril_found,
    "ramipril_active": ramipril_active,
    "ramipril_dose_10mg": ramipril_dose_ok,
    "seeded_tickler_no": seeded_tickler_no,
    "tickler_initial_status": initial_tickler_status,
    "tickler_current_status": tickler_current_status,
    "tickler_resolved": tickler_resolved,
    "export_timestamp": __import__('datetime').datetime.now().isoformat()
}

with open('/tmp/multi_feature_encounter_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Export: {new_measurements} new measurements (BP={has_bp}, value={bp_value})")
print(f"        {new_drugs} new drugs (Ramipril={ramipril_found}, active={ramipril_active})")
print(f"        Tickler: initial={initial_tickler_status}, current={tickler_current_status}, resolved={tickler_resolved}")
PYEOF

echo "Result saved to /tmp/multi_feature_encounter_result.json"
echo "=== Export Complete ==="
