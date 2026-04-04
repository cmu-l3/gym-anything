#!/bin/bash
# Export results: specialist_referral_workup
# Patient: Kelle Crist (ID 9)

source /workspace/scripts/task_utils.sh

PATIENT_ID=9
RESULT_FILE="/tmp/specialist_referral_workup_result.json"

echo "=== Exporting specialist_referral_workup results for patient $PATIENT_ID ==="

# Read initial baselines
INITIAL_PROBLEMS=$(cat /tmp/srw_initial_problems 2>/dev/null || echo "0")
INITIAL_ALLERGIES=$(cat /tmp/srw_initial_allergies 2>/dev/null || echo "0")
INITIAL_MEDS=$(cat /tmp/srw_initial_meds 2>/dev/null || echo "0")
INITIAL_NOTES=$(cat /tmp/srw_initial_notes 2>/dev/null || echo "0")
INITIAL_REFERRALS=$(cat /tmp/srw_initial_referrals 2>/dev/null || echo "0")

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

echo "Baselines — problems: $INITIAL_PROBLEMS, allergies: $INITIAL_ALLERGIES, meds: $INITIAL_MEDS, notes: $INITIAL_NOTES, referrals: $INITIAL_REFERRALS"

python3 << PYEOF
import subprocess
import json
import os

PATIENT_ID = 9
result_file = "$RESULT_FILE"
initial_problems = int("$INITIAL_PROBLEMS".strip() or "0")
initial_allergies = int("$INITIAL_ALLERGIES".strip() or "0")
initial_meds = int("$INITIAL_MEDS".strip() or "0")
initial_notes = int("$INITIAL_NOTES".strip() or "0")
initial_referrals = int("$INITIAL_REFERRALS".strip() or "0")
task_start = int("$TASK_START".strip() or "0")

def query(sql):
    cmd = ["mysql", "-u", "freemed", "-pfreemed", "freemed", "-N", "-e", sql]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        return r.stdout.strip()
    except Exception as e:
        return ""

# ----- Problem list -----
prob_raw = query(f"SELECT problem_code, problem, problem_onset FROM current_problems WHERE ppatient={PATIENT_ID}")
problems = []
problem_codes = []
for line in prob_raw.splitlines():
    parts = line.split("\t")
    code = parts[0].strip() if len(parts) > 0 else ""
    name = parts[1].strip() if len(parts) > 1 else ""
    onset = parts[2].strip() if len(parts) > 2 else ""
    if code:
        problem_codes.append(code)
        problems.append({"code": code, "name": name, "onset": onset})
prob_count_raw = query(f"SELECT COUNT(*) FROM current_problems WHERE ppatient={PATIENT_ID}")
prob_count = int(prob_count_raw.strip() or "0")

# ----- Allergies -----
allergy_raw = query(f"SELECT allergy, reaction, severity FROM allergies_atomic WHERE patient={PATIENT_ID}")
allergies = []
for line in allergy_raw.splitlines():
    parts = line.split("\t")
    allergen = parts[0].strip() if len(parts) > 0 else ""
    reaction = parts[1].strip() if len(parts) > 1 else ""
    severity = parts[2].strip() if len(parts) > 2 else ""
    if allergen:
        allergies.append({"allergy": allergen, "reaction": reaction, "severity": severity})
allergy_count_raw = query(f"SELECT COUNT(*) FROM allergies_atomic WHERE patient={PATIENT_ID}")
allergy_count = int(allergy_count_raw.strip() or "0")

# ----- Medications -----
med_raw = query(f"SELECT mdrugs, mdose, mquantity, mrefills FROM medications WHERE mpatient={PATIENT_ID}")
medications = []
for line in med_raw.splitlines():
    parts = line.split("\t")
    drug = parts[0].strip() if len(parts) > 0 else ""
    dose = parts[1].strip() if len(parts) > 1 else ""
    qty = parts[2].strip() if len(parts) > 2 else ""
    refills = parts[3].strip() if len(parts) > 3 else ""
    if drug:
        medications.append({"drug": drug, "dose": dose, "quantity": qty, "refills": refills})
meds_count_raw = query(f"SELECT COUNT(*) FROM medications WHERE mpatient={PATIENT_ID}")
meds_count = int(meds_count_raw.strip() or "0")

# ----- Clinical notes -----
notes_raw = query(f"SELECT pnotesdate, pnotetext FROM pnotes WHERE pnotespat={PATIENT_ID} ORDER BY pnotesdate DESC LIMIT 1")
note_text = ""
note_date = ""
for line in notes_raw.splitlines():
    parts = line.split("\t")
    note_date = parts[0].strip() if len(parts) > 0 else ""
    note_text = parts[1].strip() if len(parts) > 1 else ""
    break
notes_count_raw = query(f"SELECT COUNT(*) FROM pnotes WHERE pnotespat={PATIENT_ID}")
notes_count = int(notes_count_raw.strip() or "0")

# ----- Referrals -----
ref_raw = query(f"SELECT referral_to, specialty, reason, referral_date FROM referrals WHERE patient={PATIENT_ID}")
referrals = []
for line in ref_raw.splitlines():
    parts = line.split("\t")
    ref_to = parts[0].strip() if len(parts) > 0 else ""
    specialty = parts[1].strip() if len(parts) > 1 else ""
    reason = parts[2].strip() if len(parts) > 2 else ""
    ref_date = parts[3].strip() if len(parts) > 3 else ""
    if ref_to or specialty:
        referrals.append({"referral_to": ref_to, "specialty": specialty, "reason": reason, "date": ref_date})
ref_count_raw = query(f"SELECT COUNT(*) FROM referrals WHERE patient={PATIENT_ID}")
ref_count = int(ref_count_raw.strip() or "0")

result = {
    "patient_id": PATIENT_ID,
    "task_start": task_start,
    "problem_codes": problem_codes,
    "problems": problems,
    "prob_count": prob_count,
    "initial_problems": initial_problems,
    "allergies": allergies,
    "allergy_count": allergy_count,
    "initial_allergies": initial_allergies,
    "medications": medications,
    "meds_count": meds_count,
    "initial_meds": initial_meds,
    "note_text": note_text,
    "note_date": note_date,
    "notes_count": notes_count,
    "initial_notes": initial_notes,
    "referrals": referrals,
    "ref_count": ref_count,
    "initial_referrals": initial_referrals,
}

with open(result_file, "w") as f:
    json.dump(result, f, indent=2)

print(f"Exported: problems={len(problem_codes)}, allergies={len(allergies)}, meds={len(medications)}, notes_count={notes_count}, referrals={len(referrals)}")
print(f"Result written to {result_file}")
PYEOF

echo "=== Export complete ==="
