#!/bin/bash
# Export results: chart_audit_corrections
# Patients: Malka Hartmann (ID 12), Myrtis Armstrong (ID 16), Arlie McClure (ID 17)

source /workspace/scripts/task_utils.sh

P1=12
P2=16
P3=17
RESULT_FILE="/tmp/chart_audit_corrections_result.json"

echo "=== Exporting chart_audit_corrections results ==="

INITIAL_P1_PHONE=$(cat /tmp/cac_p1_phone 2>/dev/null | tr -d '\n')
INITIAL_P2_ALLERGY_COUNT=$(cat /tmp/cac_p2_allergy_count 2>/dev/null || echo "0")
INITIAL_P3_PROBLEM_COUNT=$(cat /tmp/cac_p3_problem_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

python3 << PYEOF
import subprocess
import json

P1, P2, P3 = 12, 16, 17
result_file = "$RESULT_FILE"
initial_p1_phone = "$INITIAL_P1_PHONE".strip()
initial_p2_allergies = int("$INITIAL_P2_ALLERGY_COUNT".strip() or "0")
initial_p3_problems = int("$INITIAL_P3_PROBLEM_COUNT".strip() or "0")
task_start = int("$TASK_START".strip() or "0")

def query(sql):
    cmd = ["mysql", "-u", "freemed", "-pfreemed", "freemed", "-N", "-e", sql]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        return r.stdout.strip()
    except Exception:
        return ""

# ----- Patient 1: Malka Hartmann demographics -----
p1_demo_raw = query(f"SELECT ptfname, ptlname, ptdob, pthphone, ptemail FROM patient WHERE id={P1}")
p1_data = {}
for line in p1_demo_raw.splitlines():
    parts = line.split("\t")
    p1_data = {
        "fname": parts[0].strip() if len(parts) > 0 else "",
        "lname": parts[1].strip() if len(parts) > 1 else "",
        "dob":   parts[2].strip() if len(parts) > 2 else "",
        "phone": parts[3].strip() if len(parts) > 3 else "",
        "email": parts[4].strip() if len(parts) > 4 else "",
    }
    break

# ----- Patient 2: Myrtis Armstrong allergies -----
p2_allergy_raw = query(f"SELECT allergy, reaction, severity FROM allergies_atomic WHERE patient={P2}")
p2_allergies = []
for line in p2_allergy_raw.splitlines():
    parts = line.split("\t")
    allergen  = parts[0].strip() if len(parts) > 0 else ""
    reaction  = parts[1].strip() if len(parts) > 1 else ""
    severity  = parts[2].strip() if len(parts) > 2 else ""
    if allergen:
        p2_allergies.append({"allergy": allergen, "reaction": reaction, "severity": severity})
p2_allergy_count_raw = query(f"SELECT COUNT(*) FROM allergies_atomic WHERE patient={P2}")
p2_allergy_count = int(p2_allergy_count_raw.strip() or "0")

# ----- Patient 3: Arlie McClure problem list -----
p3_prob_raw = query(f"SELECT problem_code, problem, problem_onset FROM current_problems WHERE ppatient={P3}")
p3_problems = []
p3_problem_codes = []
for line in p3_prob_raw.splitlines():
    parts = line.split("\t")
    code  = parts[0].strip() if len(parts) > 0 else ""
    name  = parts[1].strip() if len(parts) > 1 else ""
    onset = parts[2].strip() if len(parts) > 2 else ""
    if code:
        p3_problem_codes.append(code)
        p3_problems.append({"code": code, "name": name, "onset": onset})
p3_prob_count_raw = query(f"SELECT COUNT(*) FROM current_problems WHERE ppatient={P3}")
p3_prob_count = int(p3_prob_count_raw.strip() or "0")

result = {
    "task_start": task_start,
    "patient_12": {
        "id": P1,
        "data": p1_data,
        "initial_phone": initial_p1_phone,
    },
    "patient_16": {
        "id": P2,
        "allergies": p2_allergies,
        "allergy_count": p2_allergy_count,
        "initial_allergy_count": initial_p2_allergies,
    },
    "patient_17": {
        "id": P3,
        "problem_codes": p3_problem_codes,
        "problems": p3_problems,
        "prob_count": p3_prob_count,
        "initial_prob_count": initial_p3_problems,
    },
}

with open(result_file, "w") as f:
    json.dump(result, f, indent=2)

print(f"P12 phone={p1_data.get('phone')}, P16 allergies={len(p2_allergies)}, P17 problems={len(p3_problems)}")
print(f"Result written to {result_file}")
PYEOF

echo "=== Export complete ==="
