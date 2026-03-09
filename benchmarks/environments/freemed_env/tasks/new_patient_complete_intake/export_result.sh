#!/bin/bash
# Export result: new_patient_complete_intake
# New patient: Helena Vasquez

echo "=== Exporting new_patient_complete_intake Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/new_patient_complete_intake_end.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/npci_initial_patient_count 2>/dev/null || echo "0")

python3 << PYEOF
import subprocess, json

TASK_START = int("$TASK_START")
INITIAL_PATIENT_COUNT = int("$INITIAL_COUNT")

def q(sql):
    r = subprocess.run(
        ['mysql', '-u', 'freemed', '-pfreemed', 'freemed', '-N', '-e', sql],
        capture_output=True, text=True
    )
    return r.stdout.strip()

# --- Find Helena Vasquez ---
patient_raw = q("SELECT id, ptfname, ptlname, ptdob, ptsex, ptaddr1, ptcity, ptstate, ptzip, pthphone, ptemail FROM patient WHERE ptfname='Helena' AND ptlname='Vasquez' LIMIT 1")

patient_found = bool(patient_raw.strip())
patient_data = {}
patient_id = None

if patient_raw.strip():
    parts = patient_raw.strip().split('\t')
    patient_id = int(parts[0]) if len(parts) > 0 and parts[0].strip() else None
    patient_data = {
        "id": patient_id,
        "fname": parts[1].strip() if len(parts) > 1 else "",
        "lname": parts[2].strip() if len(parts) > 2 else "",
        "dob": parts[3].strip() if len(parts) > 3 else "",
        "sex": parts[4].strip() if len(parts) > 4 else "",
        "addr": parts[5].strip() if len(parts) > 5 else "",
        "city": parts[6].strip() if len(parts) > 6 else "",
        "state": parts[7].strip() if len(parts) > 7 else "",
        "zip": parts[8].strip() if len(parts) > 8 else "",
        "phone": parts[9].strip() if len(parts) > 9 else "",
        "email": parts[10].strip() if len(parts) > 10 else "",
    }

current_patient_count = int(q("SELECT COUNT(*) FROM patient") or "0")

# --- Problem list ---
problems = []
if patient_id:
    probs_raw = q(f"SELECT problem, problem_code FROM current_problems WHERE ppatient={patient_id}")
    if probs_raw:
        for line in probs_raw.split('\n'):
            if not line.strip():
                continue
            parts = line.split('\t')
            problems.append({
                "text": parts[0].strip() if len(parts) > 0 else "",
                "code": parts[1].strip() if len(parts) > 1 else ""
            })

problem_codes = [p["code"] for p in problems]

# --- Medications ---
medications = []
if patient_id:
    meds_raw = q(f"SELECT mdrugs, mdose, mquantity, mrefills FROM medications WHERE mpatient={patient_id} ORDER BY id DESC LIMIT 10")
    if meds_raw:
        for line in meds_raw.split('\n'):
            if not line.strip():
                continue
            parts = line.split('\t')
            medications.append({
                "drug": parts[0].strip() if len(parts) > 0 else "",
                "dose": parts[1].strip() if len(parts) > 1 else "",
                "quantity": parts[2].strip() if len(parts) > 2 else "",
                "refills": parts[3].strip() if len(parts) > 3 else ""
            })

# --- Allergies ---
allergies = []
if patient_id:
    allergy_raw = q(f"SELECT allergy, reaction, severity FROM allergies_atomic WHERE patient={patient_id} ORDER BY id DESC LIMIT 10")
    if allergy_raw:
        for line in allergy_raw.split('\n'):
            if not line.strip():
                continue
            parts = line.split('\t')
            allergies.append({
                "allergy": parts[0].strip() if len(parts) > 0 else "",
                "reaction": parts[1].strip() if len(parts) > 1 else "",
                "severity": parts[2].strip() if len(parts) > 2 else ""
            })

result = {
    "task_start": TASK_START,
    "initial_patient_count": INITIAL_PATIENT_COUNT,
    "current_patient_count": current_patient_count,
    "patient_found": patient_found,
    "patient_data": patient_data,
    "patient_id": patient_id,
    "problems": problems,
    "problem_codes": problem_codes,
    "medications": medications,
    "allergies": allergies
}

with open("/tmp/new_patient_complete_intake_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete.")
print(f"  Patient found: {patient_found} (ID: {patient_id})")
print(f"  Problems: {problem_codes}")
print(f"  Medications: {[m['drug'] for m in medications]}")
print(f"  Allergies: {[a['allergy'] for a in allergies]}")
PYEOF

echo "=== Export Complete ==="
