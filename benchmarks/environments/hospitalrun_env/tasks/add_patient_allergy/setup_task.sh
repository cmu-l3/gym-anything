#!/bin/bash
set -e
echo "=== Setting up add_patient_allergy task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Wait for HospitalRun to be ready
echo "Checking HospitalRun availability..."
for i in $(seq 1 30); do
    if curl -s http://localhost:3000/ > /dev/null; then
        echo "HospitalRun is ready."
        break
    fi
    sleep 2
done

# 3. Ensure Patient Elena Vasiliev exists (re-seed if missing)
# We check for p1_0000006 which corresponds to Elena Vasiliev in the seed data
echo "Verifying patient Elena Vasiliev..."
PATIENT_CHECK=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_0000006" 2>/dev/null | grep -o "Elena") || true

if [ -z "$PATIENT_CHECK" ]; then
    echo "Re-seeding patient Elena Vasiliev..."
    # Minimal patient doc required for the task
    curl -s -X PUT "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/patient_p1_0000006" \
        -H "Content-Type: application/json" \
        -d '{
          "data": {
            "friendlyId": "P00006",
            "firstName": "Elena",
            "lastName": "Vasiliev",
            "sex": "Female",
            "dateOfBirth": "1985-05-20",
            "patientType": "Charity",
            "phone": "555-0199",
            "email": "elena.v@example.com",
            "address": "42 Nevsky Prospekt",
            "status": "Active"
          }
        }' > /dev/null || true
fi

# 4. Clean up specific allergies for this patient (Idempotency)
# We want to remove any existing Penicillin, Sulfa, or Latex allergies for Elena
echo "Cleaning up previous allergy records for Elena Vasiliev..."
ALL_DOCS=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true")

# Use python to filter and generate delete commands
echo "$ALL_DOCS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
to_delete = []
target_allergies = ['penicillin', 'sulfa', 'latex']
patient_id_frag = 'p1_0000006'

for row in data.get('rows', []):
    doc = row.get('doc', {})
    d = doc.get('data', doc) # HospitalRun often wraps in 'data'
    
    # Check if it's an allergy doc or likely an allergy
    doc_type = d.get('type', doc.get('type', ''))
    doc_id = doc.get('_id', '')
    
    is_allergy_type = (doc_type == 'allergy' or doc_id.startswith('allergy_'))
    
    # Check linkage to Elena
    patient_ref = str(d.get('patient', ''))
    is_linked = (patient_id_frag in patient_ref)
    
    if is_allergy_type and is_linked:
        name = d.get('name', '').lower()
        # Delete if it matches our target list (so agent has to re-add them)
        if any(t in name for t in target_allergies):
            print(f\"{doc.get('_id')}|{doc.get('_rev')}\")
" | while IFS='|' read -r doc_id rev; do
    if [ -n "$doc_id" ]; then
        echo "Deleting stale allergy: $doc_id"
        curl -s -X DELETE "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${doc_id}?rev=${rev}" > /dev/null
    fi
done

# 5. Launch Firefox and clean session
pkill -f firefox || true
rm -rf /home/ga/.mozilla/firefox/*.default*/sessionstore-backups
rm -rf /home/ga/.mozilla/firefox/*.default*/sessionstore.js

echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox http://localhost:3000/ &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "HospitalRun"; then
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Capture Initial State
sleep 5
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="