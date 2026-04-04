#!/bin/bash
# Export script for Record Vitals and Note task in OSCAR EMR
# Queries measurements and encounter notes for Maria Santos

echo "=== Exporting Record Vitals and Note Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

PATIENT_NO=$(cat /tmp/task_patient_no_vitals 2>/dev/null || oscar_query "SELECT demographic_no FROM demographic WHERE first_name='Maria' AND last_name='Santos' LIMIT 1")
INITIAL_MEASUREMENT_COUNT=$(cat /tmp/initial_measurement_count 2>/dev/null || echo "0")
INITIAL_NOTE_COUNT=$(cat /tmp/initial_note_count 2>/dev/null || echo "0")

echo "Patient demographic_no: $PATIENT_NO"

# Query current measurements for Maria Santos
CURRENT_MEASUREMENT_COUNT=$(oscar_query "SELECT COUNT(*) FROM measurements WHERE demographicNo='$PATIENT_NO'" || echo "0")

# Get all measurement types and values
MEASUREMENTS_RAW=$(oscar_query "SELECT type, dataField FROM measurements WHERE demographicNo='$PATIENT_NO' ORDER BY id DESC" 2>/dev/null || echo "")

# Query encounter notes
CURRENT_NOTE_COUNT=$(oscar_query "SELECT COUNT(*) FROM casemgmt_note WHERE demographic_no='$PATIENT_NO' AND archived=0" || echo "0")

# Get most recent note text (first 500 chars for analysis)
LATEST_NOTE=$(oscar_query "SELECT LEFT(note, 500) FROM casemgmt_note WHERE demographic_no='$PATIENT_NO' AND archived=0 ORDER BY note_id DESC LIMIT 1" 2>/dev/null || echo "")

# Use Python to assemble JSON robustly
python3 << PYEOF
import json, subprocess, sys

patient_no = "${PATIENT_NO}"
initial_meas = int("${INITIAL_MEASUREMENT_COUNT}".strip() or "0")
initial_notes = int("${INITIAL_NOTE_COUNT}".strip() or "0")
current_meas = int("${CURRENT_MEASUREMENT_COUNT}".strip() or "0")
current_notes = int("${CURRENT_NOTE_COUNT}".strip() or "0")
latest_note = """${LATEST_NOTE}"""

# Re-query measurements with full data
def run_query(q):
    try:
        r = subprocess.run(
            ['docker', 'exec', 'oscar-db', 'mysql', '-u', 'oscar', '-poscar', 'oscar', '-N', '-e', q],
            capture_output=True, text=True, timeout=15
        )
        return r.stdout.strip()
    except Exception as e:
        return ""

meas_rows = run_query(f"SELECT type, dataField FROM measurements WHERE demographicNo={patient_no} ORDER BY id DESC")
note_content = run_query(f"SELECT LEFT(note, 1000) FROM casemgmt_note WHERE demographic_no={patient_no} AND archived=0 ORDER BY note_id DESC LIMIT 1")

# Analyze measurements
all_types = []
all_values = []
has_bp = False
has_weight = False
has_height = False
bp_value = ""
weight_value = ""
height_value = ""

for line in meas_rows.splitlines():
    parts = line.split('\t')
    if len(parts) >= 2:
        mtype = parts[0].lower().strip()
        mval = parts[1].strip()
        all_types.append(parts[0])
        all_values.append(mval)
        if 'bp' in mtype or 'blood' in mtype or 'pressure' in mtype:
            has_bp = True
            bp_value = mval
        if mtype in ('wt', 'weight', 'wght') or 'weight' in mtype:
            has_weight = True
            weight_value = mval
        if mtype in ('ht', 'height', 'hght') or 'height' in mtype:
            has_height = True
            height_value = mval
        # Check values for BP pattern (e.g., "118/76" or "118" with another "76")
        if '/' in mval and any(c.isdigit() for c in mval):
            has_bp = True
            bp_value = mval

# Check note content
note_lower = note_content.lower()
has_annual_physical = any(kw in note_lower for kw in ['annual', 'physical', 'yearly', 'routine exam'])
has_bmi = 'bmi' in note_lower or '22' in note_lower
has_note_content = len(note_content.strip()) > 50

new_measurements = current_meas - initial_meas
new_notes = current_notes - initial_notes

result = {
    "patient_no": patient_no,
    "patient_fname": "Maria",
    "patient_lname": "Santos",
    "initial_measurement_count": initial_meas,
    "current_measurement_count": current_meas,
    "new_measurement_count": new_measurements,
    "measurement_types": all_types,
    "measurement_values": all_values,
    "has_bp_measurement": has_bp,
    "bp_value": bp_value,
    "has_weight_measurement": has_weight,
    "weight_value": weight_value,
    "has_height_measurement": has_height,
    "height_value": height_value,
    "initial_note_count": initial_notes,
    "current_note_count": current_notes,
    "new_note_count": new_notes,
    "latest_note_excerpt": note_content[:300] if note_content else "",
    "note_has_annual_physical": has_annual_physical,
    "note_has_bmi": has_bmi,
    "note_has_content": has_note_content,
    "export_timestamp": __import__('datetime').datetime.now().isoformat()
}

with open('/tmp/record_vitals_and_note_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print(f"Export: {new_measurements} new measurements, {new_notes} new notes")
print(f"  BP: {has_bp} ({bp_value}), Weight: {has_weight}, Height: {has_height}")
print(f"  Note has annual physical: {has_annual_physical}, has content: {has_note_content}")
PYEOF

echo "Result saved to /tmp/record_vitals_and_note_result.json"
echo "=== Export Complete ==="
