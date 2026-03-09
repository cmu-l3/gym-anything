#!/bin/bash
echo "=== Exporting discharge_patient results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot (Evidence)
take_screenshot /tmp/task_final.png

# 2. Extract Data from CouchDB
# We need the current state of the visit document
VISIT_DOC_JSON=$(hr_couch_get "visit_p1_200001")
PATIENT_DOC_JSON=$(hr_couch_get "patient_p1_200001")

# Save raw docs for debugging
echo "$VISIT_DOC_JSON" > /tmp/debug_visit.json
echo "$PATIENT_DOC_JSON" > /tmp/debug_patient.json

# 3. Parse relevant fields
# We need: status, endDate, _rev, and linkage to patient
export RESULT_JSON=$(python3 <<EOF
import json
import sys

try:
    visit = json.loads('''$VISIT_DOC_JSON''')
    patient = json.loads('''$PATIENT_DOC_JSON''')
    
    # HospitalRun wraps data in a 'data' property usually, but let's handle both
    v_data = visit.get('data', visit)
    p_data = patient.get('data', patient)
    
    initial_rev = ""
    try:
        with open("/tmp/initial_visit_rev.txt", "r") as f:
            initial_rev = f.read().strip()
    except:
        pass

    result = {
        "visit_exists": "_id" in visit,
        "visit_rev": visit.get("_rev", ""),
        "initial_rev": initial_rev,
        "status": v_data.get("status", ""),
        "end_date": v_data.get("endDate", ""),
        "visit_patient_ref": v_data.get("patient", ""),
        "patient_exists": "_id" in patient,
        "patient_name": f"{p_data.get('firstName','')} {p_data.get('lastName','')}".strip()
    }
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({"error": str(e)}))
EOF
)

# 4. Save to JSON file for Verifier
echo "$RESULT_JSON" > /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json