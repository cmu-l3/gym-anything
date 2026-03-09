#!/bin/bash
set -e
echo "=== Exporting create_outpatient_visit results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get task timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Query CouchDB for the newly created visit
# We look for:
# - type: visit
# - patient: patient_p1_00201
# - date created/modified > TASK_START (approx)
# Note: CouchDB doesn't strictly track 'created_at' in the doc unless app adds it,
# but we can filter by content and check if it wasn't there before.

echo "Querying CouchDB for new visits..."
PATIENT_ID="patient_p1_00201"

# Fetch all docs, filter for visits linked to our patient
# We output a JSON list of matching visits
MATCHING_VISITS=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" | \
python3 -c "
import sys, json
data = json.load(sys.stdin)
matches = []
for row in data.get('rows', []):
    doc = row.get('doc', {})
    d = doc.get('data', doc)
    
    # Check if it's a visit
    is_visit = (doc.get('type') == 'visit' or d.get('type') == 'visit')
    
    # Check link to patient (HospitalRun links by ID)
    patient_ref = d.get('patient', '')
    is_linked = ('$PATIENT_ID' in patient_ref) or ('P00201' in patient_ref)
    
    if is_visit and is_linked:
        # Extract fields for verification
        matches.append({
            'id': doc.get('_id'),
            'rev': doc.get('_rev'),
            'visitType': d.get('visitType', ''),
            'location': d.get('location', ''),
            'examiner': d.get('examiner', ''),
            'reason': d.get('reasonForVisit', ''),
            'startDate': d.get('startDate', ''),
            'endDate': d.get('endDate', '')
        })
print(json.dumps(matches))
")

# 4. Check initial count
INITIAL_COUNT=$(cat /tmp/initial_visit_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(hr_count_docs "visit")

# 5. Create result JSON
cat > /tmp/task_result.json <<EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "initial_count": $INITIAL_COUNT,
  "current_count": $CURRENT_COUNT,
  "matching_visits": $MATCHING_VISITS,
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json