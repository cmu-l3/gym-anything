#!/bin/bash
echo "=== Exporting correct_medication_dosage result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Configuration
PATIENT_ID="patient_p1_arthurdent"
TARGET_MED_ID_SUFFIX="med_amox_001"
FULL_TARGET_ID="medication_${PATIENT_ID}_${TARGET_MED_ID_SUFFIX}"

# 1. Fetch the specific target document (to check if it was edited or deleted)
echo "Fetching target document: $FULL_TARGET_ID"
TARGET_DOC=$(hr_couch_get "$FULL_TARGET_ID")
TARGET_EXISTS=$(echo "$TARGET_DOC" | grep -q "_id" && echo "true" || echo "false")
TARGET_DOSAGE=""

if [ "$TARGET_EXISTS" = "true" ]; then
    TARGET_DOSAGE=$(echo "$TARGET_DOC" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('dosage', d.get('dosage','')))" 2>/dev/null)
fi

# 2. Search for ANY Amoxicillin order for this patient (in case they deleted and re-created)
echo "Searching for any Amoxicillin order for patient..."
ANY_MATCH=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true" 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
matches = []
for row in data.get('rows', []):
    doc = row.get('doc', {})
    d = doc.get('data', doc)
    
    # Check if linked to patient
    p_ref = d.get('patient', '')
    
    # Check medication name
    med = d.get('medication', '')
    
    if ('${PATIENT_ID}' in p_ref) and ('Amoxicillin' in med):
        matches.append({
            'id': doc.get('_id'),
            'dosage': d.get('dosage', ''),
            'status': d.get('status', '')
        })
print(json.dumps(matches))
" 2>/dev/null)

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_doc_id": "$FULL_TARGET_ID",
    "target_doc_exists": $TARGET_EXISTS,
    "target_doc_dosage": "$TARGET_DOSAGE",
    "all_med_matches": $ANY_MATCH,
    "task_timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="