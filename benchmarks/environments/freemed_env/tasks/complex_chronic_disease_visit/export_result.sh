#!/bin/bash
# Export result: complex_chronic_disease_visit
# Patient: Dwight Dach (ID 6)

echo "=== Exporting complex_chronic_disease_visit Result ==="

source /workspace/scripts/task_utils.sh

PATIENT_ID=6

take_screenshot /tmp/complex_chronic_disease_visit_end.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_VITALS=$(cat /tmp/ccdv_initial_vitals 2>/dev/null || echo "0")
INITIAL_MEDS=$(cat /tmp/ccdv_initial_meds 2>/dev/null || echo "0")
INITIAL_NOTES=$(cat /tmp/ccdv_initial_notes 2>/dev/null || echo "0")

python3 << PYEOF
import subprocess, json, sys

TASK_START = int("$TASK_START")
PATIENT_ID = $PATIENT_ID
INITIAL_VITALS = int("$INITIAL_VITALS")
INITIAL_MEDS = int("$INITIAL_MEDS")
INITIAL_NOTES = int("$INITIAL_NOTES")

def q(sql):
    r = subprocess.run(
        ['mysql', '-u', 'freemed', '-pfreemed', 'freemed', '-N', '-e', sql],
        capture_output=True, text=True
    )
    return r.stdout.strip()

# --- Check diagnoses in problem list ---
probs_raw = q(f"SELECT problem, problem_code FROM current_problems WHERE ppatient={PATIENT_ID}")
problem_entries = []
if probs_raw:
    for line in probs_raw.split('\n'):
        parts = line.split('\t')
        if len(parts) >= 2:
            problem_entries.append({"text": parts[0].strip(), "code": parts[1].strip()})

problem_codes = [e["code"] for e in problem_entries]

# --- Check vitals ---
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

# --- Check medications/prescriptions ---
meds_raw = q(f"SELECT mdrugs, mdose, mquantity, mrefills FROM medications WHERE mpatient={PATIENT_ID} ORDER BY id DESC LIMIT 10")
medications = []
if meds_raw:
    for line in meds_raw.split('\n'):
        if not line.strip():
            continue
        parts = line.split('\t')
        if len(parts) >= 1:
            med = {
                "drug": parts[0].strip() if len(parts) > 0 else "",
                "dose": parts[1].strip() if len(parts) > 1 else "",
                "quantity": parts[2].strip() if len(parts) > 2 else "",
                "refills": parts[3].strip() if len(parts) > 3 else ""
            }
            medications.append(med)

meds_count = int(q(f"SELECT COUNT(*) FROM medications WHERE mpatient={PATIENT_ID}") or "0")

# --- Check clinical notes ---
notes_raw = q(f"SELECT pnotetext FROM pnotes WHERE pnotespat={PATIENT_ID} ORDER BY id DESC LIMIT 1")
note_text = notes_raw.strip() if notes_raw else ""
notes_count = int(q(f"SELECT COUNT(*) FROM pnotes WHERE pnotespat={PATIENT_ID}") or "0")

result = {
    "task_start": TASK_START,
    "patient_id": PATIENT_ID,
    "problem_entries": problem_entries,
    "problem_codes": problem_codes,
    "vitals": vitals,
    "vitals_count": vitals_count,
    "initial_vitals": INITIAL_VITALS,
    "medications": medications,
    "meds_count": meds_count,
    "initial_meds": INITIAL_MEDS,
    "note_text": note_text,
    "notes_count": notes_count,
    "initial_notes": INITIAL_NOTES
}

with open("/tmp/complex_chronic_disease_visit_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete.")
print(f"  Problem codes found: {problem_codes}")
print(f"  Vitals: {vitals}")
print(f"  Medications count: {meds_count} (initial: {INITIAL_MEDS})")
print(f"  Notes count: {notes_count} (initial: {INITIAL_NOTES})")
PYEOF

echo "=== Export Complete ==="
