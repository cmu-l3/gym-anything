#!/bin/bash
echo "=== Exporting return_medication result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get task timings
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Search for the return record in CouchDB
# We look for documents created/modified AFTER task start
# that reference the patient and are likely return records.
# In HospitalRun, returns might be "medication" type with status "Returned" 
# or specific return objects depending on version. We search broadly.

echo "Querying CouchDB for new documents..."

# Helper to fetch all docs and filter with python
# We look for ANY document that:
# 1. Is linked to patient 'patient_p1_marcus'
# 2. Has 'Amoxicillin' in it
# 3. Mention 'Return' or has the specific quantity '12'
# 4. Was NOT the initial seeded document (check ID)

PYTHON_SCRIPT=$(cat <<EOF
import sys, json, time

try:
    data = json.load(sys.stdin)
    rows = data.get('rows', [])
    
    matches = []
    
    seed_id = "medication_p1_amox_marcus"
    target_patient = "patient_p1_marcus"
    
    for row in rows:
        doc = row.get('doc', {})
        doc_id = doc.get('_id', '')
        
        # Skip design docs
        if doc_id.startswith('_design'): continue
        
        # Skip the original seeded doc (unless it was modified to become the return)
        # Note: HospitalRun might create a NEW doc for the return transaction
        
        doc_str = json.dumps(doc).lower()
        
        # Check for key indicators
        is_patient = target_patient in doc_str or "marcus" in doc_str
        is_med = "amoxicillin" in doc_str
        is_return = "return" in doc_str or "discharged early" in doc_str
        has_qty = "12" in doc_str
        
        if is_patient and is_med and (is_return or has_qty):
            matches.append(doc)

    print(json.dumps(matches))
except Exception as e:
    print(json.dumps({"error": str(e)}))
EOF
)

# Fetch all docs with include_docs
ALL_DOCS=$(curl -s "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true")
MATCHING_DOCS=$(echo "$ALL_DOCS" | python3 -c "$PYTHON_SCRIPT")

# 4. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "matching_docs": $MATCHING_DOCS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"