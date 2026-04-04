#!/bin/bash
set -e
echo "=== Exporting resolve_patient_diagnosis results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get the seeded patient and diagnosis IDs
PATIENT_ID="patient_oliver_sacks"
DIAGNOSIS_ID="diagnosis_oliver_bronchitis"

# 3. Fetch the specific seeded diagnosis document to check for updates
echo "Fetching target diagnosis document..."
TARGET_DOC=$(hr_couch_get "$DIAGNOSIS_ID")

# 4. Fetch ALL diagnoses for the patient to check for duplicates
# (Anti-gaming: ensure they didn't just create a new one)
echo "Fetching all diagnoses for patient..."
ALL_DIAGNOSES=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" \
    2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
results = []
for row in data.get('rows', []):
    doc = row.get('doc', {})
    d = doc.get('data', doc)
    
    # Check linkage to patient
    patient_ref = d.get('patient', '')
    is_oliver = patient_ref == '${PATIENT_ID}' or ('Oliver' in str(d) and 'Sacks' in str(d))
    
    # Check type
    is_diag = doc.get('type') == 'diagnosis' or d.get('type') == 'diagnosis' or 'diagnosis' in row['id']
    
    if is_oliver and is_diag:
        results.append(doc)
print(json.dumps(results))
")

# 5. Read initial count
INITIAL_COUNT=$(cat /tmp/initial_diagnosis_count.txt 2>/dev/null || echo "1")

# 6. Construct result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" <<EOF
{
  "target_diagnosis_doc": $TARGET_DOC,
  "all_diagnoses": $ALL_DIAGNOSES,
  "initial_count": $INITIAL_COUNT,
  "task_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="